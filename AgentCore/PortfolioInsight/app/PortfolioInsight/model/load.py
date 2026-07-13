import os

from strands.models.bedrock import BedrockModel

# 本帳號驗證過 us. profile 可用;claude-haiku-4-5 會 AccessDenied(Marketplace 訂閱),別換成它
DEFAULT_MODEL_ID = "us.anthropic.claude-sonnet-4-5-20250929-v1:0"


def load_model() -> BedrockModel:
    """Get Bedrock model client using IAM credentials."""
    return BedrockModel(model_id=os.environ.get("MODEL_ID", DEFAULT_MODEL_ID))
