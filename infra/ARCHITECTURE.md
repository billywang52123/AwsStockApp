# StockMood 雲端架構(as-built)— 網路 / IAM / 安全設計

本文記錄**實際部署出來**的架構與設計理由,並誠實標註「符合最佳實踐」與「為黑客松刻意妥協、上線前該補強」之處。
對應 CDK:`infra/stacks/`。區域 us-east-1,全資源帶 tag `Project=StockMood-Hackathon`。

---

## 1. 網路架構(VPC)

```
                          Internet
                             │
                        Internet Gateway
                             │
        ┌────────────────────┴─────────────────────┐
        │            VPC 10.0.0.0/16 (2 AZ)          │
        │                                            │
        │  ┌─ public 子網 (2×/24) ───────────────┐   │
        │  │  • internet-facing ALB(ECS Express)│   │
        │  │  • Fargate task(public IP,走 IGW)  │   │
        │  └────────────────────────────────────┘   │
        │  ┌─ app 子網 PRIVATE_WITH_EGRESS (2×/24)┐  │
        │  │  • 目前無人使用(原設計放 task)      │  │
        │  └────────────────────────────────────┘   │
        │  ┌─ db 子網 PRIVATE_ISOLATED (2×/24) ──┐   │
        │  │  • RDS PostgreSQL(無對外路由)       │   │
        │  └────────────────────────────────────┘   │
        └────────────────────────────────────────────┘
```

**設計理由**
- **三層子網分離**(public / app / db):經典分層,把「對外入口」「應用」「資料」隔在不同信任邊界。
- **2 個 AZ**:高可用基礎(RDS 與 ALB 跨 AZ)。
- **RDS 放 PRIVATE_ISOLATED**:資料庫**完全無對外路由**,只能從 VPC 內部連——資料層最小暴露面。
- **無 NAT Gateway**:task 在 public 子網走 IGW 對外(拉 ECR 映像、呼叫 Bedrock/Secrets Manager);私有 app 子網目前無人使用,NAT 純浪費成本故移除(省 ~$32/月)。

**妥協點(上線前補強)**
- ⚠️ **task 跑在 public 子網、帶 public IP**:這是 **ECS Express Mode 的先天限制**——它只吃單一子網清單,子網型別決定 ALB 對外與否,要 internet-facing ALB 就得放 public 子網。task 雖有 public IP 但受 service SG 保護(只有 ALB 能打 app port)。正式環境較佳做法是 ALB 在 public、task 在 private(需 NAT 或 VPC Endpoints),但 Express L1 不支援分離。

---

## 2. IAM 設計(最小權限)

ECS Express 用**三個職責分離**的角色,而非一個大權限角色:

| 角色 | 信任主體 | 權限 | 用途 |
|---|---|---|---|
| **InfrastructureRole** | `ecs.amazonaws.com` | AWS 託管 `service-role/AmazonECSInfrastructureRoleforExpressGatewayServices` | 讓 ECS 代建 ALB / SG / ACM 憑證 / autoscaling |
| **ExecutionRole** | `ecs-tasks.amazonaws.com` | 託管 `AmazonECSTaskExecutionRolePolicy` + **只讀 `stockmood/app` 密鑰** | 拉 ECR 映像、啟動時注入密鑰 |
| **TaskRole** | `ecs-tasks.amazonaws.com` | `bedrock:InvokeModel` + **只讀 `stockmood/db` 密鑰** | 執行中容器的身分:呼叫 Bedrock、取 DB 憑證 |

**設計理由**
- **Execution vs Task 角色分離**(AWS 最佳實踐):拉映像/注密鑰的權限,與「跑起來的程式碼能做什麼」分開。即使應用被入侵,拿到的是 TaskRole(只能 InvokeModel + 讀 DB 密鑰),碰不到映像倉庫等。
- **密鑰讀取用 `grant_read` 精準授權**:ExecutionRole 只讀 app 密鑰、TaskRole 只讀 db 密鑰,各取所需,非全域 `secretsmanager:*`。
- **無長期金鑰**:全程用 IAM 角色,Bedrock 免 API key、DB 憑證從 Secrets Manager runtime 取得,環境變數與 CFN 模板裡沒有任何明碼機密。

**妥協點(上線前補強)**
- ⚠️ `bedrock:InvokeModel` 的 **Resource 是 `*`**:可收斂到特定模型 / inference profile ARN。
- ⚠️ Service-linked roles(`AWSServiceRoleForECS`、`AWSServiceRoleForApplicationAutoScaling_ECSService`)由 `deploy.sh` 建立。

---

## 3. 安全群組(Security Group)

| SG | Inbound | 說明 |
|---|---|---|
| **db_sg**(RDS) | 只允許來自 **service_sg** 的 **5432** | 資料庫只接受應用服務連線,不對外、不對整個 VPC |
| **service_sg**(task) | 由 ECS Express 管理(只有 ALB 能打 app port 8000) | 掛在 Fargate task 上 |

**設計理由**
- **SG-to-SG 規則**(非 CIDR):`db_sg` 只信任 `service_sg` 這個「身分」,而非某段 IP。之後服務擴縮、IP 變動都不影響,且最小化暴露。
- **db_sg 預設 `allow_all_outbound=False`**:資料庫不需要主動對外。

---

## 4. 密鑰與資料保護

- **`stockmood/db`**:RDS 自動產生的憑證(user/pass/host/dbname),AWS 全程代管,無人經手明碼。
- **`stockmood/app`**:`OPENAI_API_KEY`(過渡期留空 → 走規則式 fallback)/ `JWT_SECRET` / `ADMIN_API_KEY`。
- **注入方式**:app 密鑰經 ECS `secrets`(ExecutionRole 於啟動注入);DB 憑證由容器內 boto3 憑 TaskRole runtime 取得 → **機密不落環境變數、不落模板**。
- **RDS**:`publicly_accessible=False`。
- **OCR 隱私**:對帳單圖片只存在單一 request 記憶體,不落地、不進 log、不進 DB。

**妥協點(上線前補強)**
- ⚠️ RDS `removal_policy=DESTROY`、`backup_retention=0`(黑客松方便清理;正式環境要 RETAIN + 備份 + Multi-AZ + 加密金鑰輪替)。
- ⚠️ `ALLOWED_ORIGINS=*`(CORS 全開;正式要限定 App 網域)。
- ⚠️ 認證目前仍是自簽 JWT + 過渡期 `ALLOW_LEGACY_HEADER_AUTH=True`;**Cognito 尚未導入**(spec 後續階段)。

---

## 5. 符合的最佳實踐(摘要)

- ✅ 網路分層 + 資料庫完全隔離(無對外路由)
- ✅ IAM 職責分離(infra / execution / task)、最小權限密鑰讀取、無長期金鑰
- ✅ SG-to-SG 最小化網路暴露
- ✅ 機密集中 Secrets Manager,不落模板/環境變數
- ✅ 全 IaC(CDK),可重現、可版控、資源全上 tag
- ✅ 移除閒置資源(NAT)控管成本

## 6. 上線前 Hardening 清單(誠實待辦)

- [ ] 導入 Cognito(取代自簽 JWT)、關閉 legacy header auth
- [ ] `bedrock:InvokeModel` 收斂到特定模型 ARN
- [ ] CORS 限定正式 App 網域
- [ ] RDS:RETAIN + 自動備份 + Multi-AZ +(視需要)靜態加密金鑰管理
- [ ] 考慮 WAF 掛在 ALB 前、強制 HTTP→HTTPS
- [ ] 評估 task 移回 private 子網的可行性(需 NAT 或 VPC Endpoints)
- [ ] CI/CD(GitHub Actions)+ 映像用 commit SHA tag(取代 :latest)
