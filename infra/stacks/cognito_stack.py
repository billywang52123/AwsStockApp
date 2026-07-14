from pathlib import Path

from aws_cdk import Stack, CfnOutput, RemovalPolicy, Duration, SecretValue
from aws_cdk import aws_cognito as cognito
from constructs import Construct


class CognitoStack(Stack):
    """Cognito User Pool 作為 end-user 認證來源。

    - User Pool + App Client:發 RS256 JWT,後端以 JWKS 驗證(取代自簽 HS256)。
    - Hosted UI domain:提供 OAuth 授權端點(federated 登入會用到)。
    - Apple / Google 為 federated IdP,只有在 CDK context 有填對應設定時才建立
      (需各自的 client id / secret)。context 沒填就先只出 User Pool,不擋部署。

    後端驗 token 需要:
      issuer  = https://cognito-idp.{region}.amazonaws.com/{user_pool_id}
      jwks    = {issuer}/.well-known/jwks.json
      aud     = App Client ID
    """

    def __init__(self, scope: Construct, cid: str, **kwargs) -> None:
        super().__init__(scope, cid, **kwargs)

        self.user_pool = cognito.UserPool(
            self,
            "UserPool",
            user_pool_name="stockmood-users",
            self_sign_up_enabled=True,
            sign_in_aliases=cognito.SignInAliases(email=True),
            auto_verify=cognito.AutoVerifiedAttrs(email=True),
            standard_attributes=cognito.StandardAttributes(
                email=cognito.StandardAttribute(required=True, mutable=True),
                fullname=cognito.StandardAttribute(required=False, mutable=True),
            ),
            password_policy=cognito.PasswordPolicy(
                min_length=8,
                require_lowercase=True,
                require_digits=True,
                require_uppercase=False,
                require_symbols=False,
            ),
            account_recovery=cognito.AccountRecovery.EMAIL_ONLY,
            removal_policy=RemovalPolicy.DESTROY,  # 黑客松:方便清掉
        )

        # --- Federated IdP:有填 context 才建 -------------------------------
        supported_idps = [cognito.UserPoolClientIdentityProvider.COGNITO]
        idp_dependencies = []

        # 黑客松:憑證直接寫死當預設,context 有給仍可覆寫。
        # (client secret 進了 git history;賽後要換掉或刪掉這個 OAuth client)
        google_client_id = (self.node.try_get_context("google_client_id")
                            or "155358777599-kide00o4ucthin7bqfvb0ngej2h7lkp5.apps.googleusercontent.com")
        google_client_secret = (self.node.try_get_context("google_client_secret")
                                or "***REMOVED***")
        if google_client_id and google_client_secret:
            google_idp = cognito.UserPoolIdentityProviderGoogle(
                self,
                "GoogleIdP",
                user_pool=self.user_pool,
                client_id=google_client_id,
                client_secret_value=SecretValue.unsafe_plain_text(google_client_secret),
                scopes=["openid", "email", "profile"],
                attribute_mapping=cognito.AttributeMapping(
                    email=cognito.ProviderAttribute.GOOGLE_EMAIL,
                    fullname=cognito.ProviderAttribute.GOOGLE_NAME,
                ),
            )
            supported_idps.append(cognito.UserPoolClientIdentityProvider.GOOGLE)
            idp_dependencies.append(google_idp)

        apple_client_id = (self.node.try_get_context("apple_client_id")      # Services ID
                           or "com.Wbilly.StockMoodApp")
        apple_team_id = self.node.try_get_context("apple_team_id") or "8D8DJA42A"
        apple_key_id = self.node.try_get_context("apple_key_id") or "NDLY6ZTD82"
        # 私鑰可直接給內容(apple_private_key),或給 .p8 檔路徑(apple_private_key_path);
        # 都沒給就找 infra/AuthKey_<KeyID>.p8(不進版控),檔案在才建 Apple IdP。
        apple_private_key = self.node.try_get_context("apple_private_key")    # .p8 內容
        apple_private_key_path = self.node.try_get_context("apple_private_key_path")
        if not apple_private_key and not apple_private_key_path:
            default_p8 = Path(__file__).resolve().parents[1] / f"AuthKey_{apple_key_id}.p8"
            if default_p8.is_file():
                apple_private_key_path = str(default_p8)
        if not apple_private_key and apple_private_key_path:
            with open(apple_private_key_path, "r", encoding="utf-8") as f:
                apple_private_key = f.read()
        if apple_client_id and apple_team_id and apple_key_id and apple_private_key:
            apple_idp = cognito.UserPoolIdentityProviderApple(
                self,
                "AppleIdP",
                user_pool=self.user_pool,
                client_id=apple_client_id,
                team_id=apple_team_id,
                key_id=apple_key_id,
                private_key=apple_private_key,
                scopes=["name", "email"],
                attribute_mapping=cognito.AttributeMapping(
                    email=cognito.ProviderAttribute.APPLE_EMAIL,
                ),
            )
            supported_idps.append(cognito.UserPoolClientIdentityProvider.APPLE)
            idp_dependencies.append(apple_idp)

        # --- App Client ----------------------------------------------------
        callback_urls = (self.node.try_get_context("cognito_callback_urls")
                         or "stockmoodapp://callback").split(",")
        logout_urls = (self.node.try_get_context("cognito_logout_urls")
                       or "stockmoodapp://signout").split(",")

        self.user_pool_client = self.user_pool.add_client(
            "AppClient",
            user_pool_client_name="stockmood-ios",
            generate_secret=False,  # public client(行動 App)不用 client secret
            supported_identity_providers=supported_idps,
            auth_flows=cognito.AuthFlow(
                user_srp=True,
                user_password=True,
            ),
            o_auth=cognito.OAuthSettings(
                flows=cognito.OAuthFlows(authorization_code_grant=True),
                scopes=[
                    cognito.OAuthScope.OPENID,
                    cognito.OAuthScope.EMAIL,
                    cognito.OAuthScope.PROFILE,
                ],
                callback_urls=[u.strip() for u in callback_urls if u.strip()],
                logout_urls=[u.strip() for u in logout_urls if u.strip()],
            ),
            access_token_validity=Duration.hours(1),
            id_token_validity=Duration.hours(1),
            refresh_token_validity=Duration.days(90),
        )
        # IdP 必須先建好,App Client 才能引用
        for idp in idp_dependencies:
            self.user_pool_client.node.add_dependency(idp)

        # --- Hosted UI domain ---------------------------------------------
        domain_prefix = self.node.try_get_context("cognito_domain_prefix") or "stockmood-hackathon"
        self.user_pool_domain = self.user_pool.add_domain(
            "HostedUiDomain",
            cognito_domain=cognito.CognitoDomainOptions(domain_prefix=domain_prefix),
        )

        # --- Outputs(後端 / App 設定用)----------------------------------
        issuer = f"https://cognito-idp.{self.region}.amazonaws.com/{self.user_pool.user_pool_id}"
        self.issuer = issuer
        self.jwks_uri = f"{issuer}/.well-known/jwks.json"

        CfnOutput(self, "UserPoolId", value=self.user_pool.user_pool_id)
        CfnOutput(self, "UserPoolClientId", value=self.user_pool_client.user_pool_client_id)
        CfnOutput(self, "CognitoIssuer", value=issuer)
        CfnOutput(self, "CognitoJwksUri", value=self.jwks_uri)
        CfnOutput(self, "HostedUiDomain",
                  value=f"https://{domain_prefix}.auth.{self.region}.amazoncognito.com")
