# Auth RBAC — SQL migration diagrams

Source: `backend/supabase/migrations/*.sql` only.

---

## Migration apply order

```mermaid
flowchart LR
  M1["20260516100000\nauth_rbac_schema"]
  M2["20260516100100\nauth_rbac_audit_triggers"]
  M3["20260516100200\nauth_rbac_rls"]
  M4["20260516100300\nauth_rbac_functions"]
  M5["20260516100400\nauth_rbac_seed"]

  M1 --> M2 --> M3 --> M4 --> M5
```

```mermaid
flowchart TB
  subgraph M1_schema["M1 — schema"]
    T1[types: staff_role, rpc_result]
    T2[tables: organizations, branches, staff_*, roles_permissions, audit_log, app_settings, subscription_cache]
    T3[RLS ENABLE on all tables]
  end

  subgraph M2_audit["M2 — audit triggers"]
    T4[set_updated_at / set_audit_user]
    T5[apply_standard_audit_triggers × 6 tables]
  end

  subgraph M3_rls["M3 — RLS"]
    T6[JWT claim helpers]
    T7[RLS policies per table]
  end

  subgraph M4_fn["M4 — functions"]
    T8[claims + RPCs + guards]
  end

  subgraph M5_seed["M5 — seed"]
    T9[roles_permissions matrix]
    T10[bootstrap admin auth.users + staff_members]
  end

  M1_schema --> M2_audit --> M3_rls --> M4_fn --> M5_seed
```

---

## All functions — call graph

```mermaid
flowchart TB
  subgraph external["External callers"]
    GoTrue["GoTrue Auth Hook"]
    Flutter["Flutter client RPC"]
    PG["INSERT/UPDATE on audited tables"]
    Policies["RLS policy evaluation"]
  end

  subgraph jwt["JWT / RLS helpers — M3"]
    request_jwt_claims
    jwt_organization_id
    jwt_branch_ids
    jwt_staff_member_id
    jwt_staff_role
    jwt_setup_required
    current_staff_member_row
  end

  subgraph claims["Custom claims — M4"]
    get_custom_claims_uuid["get_custom_claims(uuid)"]
    get_custom_claims_event["get_custom_claims(jsonb)"]
    build_staff_claims
  end

  subgraph rpc_helpers["RPC response helpers — M4"]
    rpc_success
    rpc_error
  end

  subgraph guards["Authorization guards — M4"]
    assert_bootstrap_admin
    assert_owner_or_administrator
    organization_exists
    owner_exists
  end

  subgraph rpcs["Client RPCs — M4"]
    bootstrap_create_organization
    bootstrap_create_branch
    create_staff_account
    admin_reset_staff_password
  end

  subgraph internal["Internal only — M4"]
    create_auth_user
  end

  subgraph audit_trig["Audit triggers — M2"]
    apply_standard_audit_triggers
    set_updated_at
    set_audit_user
  end

  GoTrue --> get_custom_claims_event
  get_custom_claims_event --> build_staff_claims
  get_custom_claims_uuid --> build_staff_claims

  Flutter --> bootstrap_create_organization
  Flutter --> bootstrap_create_branch
  Flutter --> create_staff_account
  Flutter --> admin_reset_staff_password

  Policies --> jwt_organization_id
  Policies --> jwt_branch_ids
  Policies --> jwt_staff_member_id
  Policies --> jwt_staff_role
  Policies --> jwt_setup_required
  Policies --> current_staff_member_row

  jwt_organization_id --> request_jwt_claims
  jwt_branch_ids --> request_jwt_claims
  jwt_staff_member_id --> request_jwt_claims
  jwt_staff_role --> request_jwt_claims
  jwt_setup_required --> request_jwt_claims
  request_jwt_claims --> auth_jwt["auth.jwt() fallback"]

  bootstrap_create_organization --> assert_bootstrap_admin
  bootstrap_create_organization --> organization_exists
  bootstrap_create_organization --> rpc_success
  bootstrap_create_organization --> rpc_error

  bootstrap_create_branch --> assert_bootstrap_admin
  bootstrap_create_branch --> rpc_success
  bootstrap_create_branch --> rpc_error

  create_staff_account --> assert_owner_or_administrator
  create_staff_account --> organization_exists
  create_staff_account --> owner_exists
  create_staff_account --> create_auth_user
  create_staff_account --> jwt_organization_id
  create_staff_account --> rpc_success
  create_staff_account --> rpc_error

  admin_reset_staff_password --> assert_owner_or_administrator
  admin_reset_staff_password --> jwt_organization_id
  admin_reset_staff_password --> rpc_success
  admin_reset_staff_password --> rpc_error

  PG --> set_updated_at
  PG --> set_audit_user

  apply_standard_audit_triggers -.->|creates triggers| set_updated_at
  apply_standard_audit_triggers -.->|creates triggers| set_audit_user
```

---

## Function inventory by migration file

```mermaid
flowchart TB
  INV(("Functions"))

  INV --> M2
  INV --> M3
  INV --> M4

  subgraph M2["M2 · auth_rbac_audit_triggers"]
    direction TB
    M2a["set_updated_at()"]
    M2b["set_audit_user()"]
    M2c["apply_standard_audit_triggers()"]
  end

  subgraph M3["M3 · auth_rbac_rls"]
    direction TB
    M3a["request_jwt_claims()"]
    M3b["jwt_organization_id()"]
    M3c["jwt_branch_ids()"]
    M3d["jwt_staff_member_id()"]
    M3e["jwt_staff_role()"]
    M3f["jwt_setup_required()"]
    M3g["current_staff_member_row()"]
  end

  subgraph M4["M4 · auth_rbac_functions"]
    direction TB
    M4a["build_staff_claims()"]
    M4b["get_custom_claims(uuid)"]
    M4c["get_custom_claims(jsonb)"]
    M4d["rpc_success() / rpc_error()"]
    M4e["assert_bootstrap_admin()"]
    M4f["assert_owner_or_administrator()"]
    M4g["organization_exists() / owner_exists()"]
    M4h["bootstrap_create_organization()"]
    M4i["bootstrap_create_branch()"]
    M4j["create_auth_user()"]
    M4k["create_staff_account()"]
    M4l["admin_reset_staff_password()"]
  end
```

---

## Login → JWT claims → RLS

```mermaid
sequenceDiagram
  participant Client as Flutter / PostgREST
  participant GoTrue as GoTrue
  participant Hook as get_custom_claims(jsonb)
  participant Build as build_staff_claims(uuid)
  participant DB as PostgreSQL

  Client->>GoTrue: signInWithPassword
  GoTrue->>Hook: Auth Hook event user_id + claims
  Hook->>Build: build_staff_claims(user_id)
  Build->>DB: SELECT staff_members
  Build->>DB: SELECT organizations
  Build->>DB: SELECT staff_branch_assignments + branches
  Build-->>Hook: staff_member_id, role, organization_id, branch_ids, setup_required
  Hook-->>GoTrue: merged claims JSON
  GoTrue-->>Client: JWT access token

  Client->>DB: API request with JWT
  DB->>DB: request_jwt_claims()
  DB->>DB: jwt_* extractors in RLS USING / WITH CHECK
  DB-->>Client: rows allowed by policies
```

```mermaid
flowchart TB
  subgraph build["build_staff_claims"]
    A[Load active staff_members by auth_user_id]
    B{staff found?}
    C[Return empty claims]
    D[Load first non-deleted organization]
    E[Aggregate branch_ids primary first]
    F["setup_required = is_bootstrap_admin AND org IS NULL"]
    G[jsonb_build_object claims]
    A --> B
    B -->|no| C
    B -->|yes| D --> E --> F --> G
  end
```

---

## Audit trigger chain (M2)

```mermaid
flowchart LR
  subgraph tables["Tables with audit columns"]
    org[organizations]
    br[branches]
    sm[staff_members]
    sba[staff_branch_assignments]
    rp[roles_permissions]
    as[app_settings]
  end

  helper[apply_standard_audit_triggers]

  helper --> org
  helper --> br
  helper --> sm
  helper --> sba
  helper --> rp
  helper --> as

  subgraph per_table["Per-table triggers"]
    TU["BEFORE UPDATE → set_updated_at"]
    TA["BEFORE INSERT OR UPDATE → set_audit_user"]
  end

  org --> TU
  org --> TA
```

```mermaid
flowchart TB
  subgraph set_audit_user_flow["set_audit_user()"]
    I{TG_OP}
    I -->|INSERT| IC[created_by ← auth.uid]
    IC --> IU[updated_by ← auth.uid]
    IU --> IT[created_at / updated_at ← now if null]
    I -->|UPDATE| UU[updated_by ← auth.uid]
  end

  subgraph set_updated_at_flow["set_updated_at()"]
    U[updated_at ← now]
  end
```

---

## RLS policies → JWT helpers

```mermaid
flowchart TB
  JWT[request.jwt.claims / auth.jwt]
  JWT --> RJC[request_jwt_claims]

  RJC --> JOID[jwt_organization_id]
  RJC --> JBID[jwt_branch_ids]
  RJC --> JSM[jwt_staff_member_id]
  RJC --> JR[jwt_staff_role]
  RJC --> JSR[jwt_setup_required]

  JOID --> P_ORG[organizations policies]
  JSR --> P_ORG
  CSM[current_staff_member_row] --> P_ORG

  JOID --> P_BR[branches policies]
  JBID --> P_BR

  JOID --> P_SM[staff_members policies]
  auth_uid[auth.uid] --> P_SM

  JBID --> P_SBA[staff_branch_assignments policies]
  JSM --> P_SBA
  JSR --> P_SBA

  P_RP[roles_permissions SELECT granted only]

  JOID --> P_AL[audit_log policies]
  auth_uid --> P_AL

  JOID --> P_AS[app_settings policies]
  JBID --> P_AS

  JOID --> P_SC[subscription_cache policies]
```

```mermaid
flowchart LR
  subgraph blocked["Direct INSERT blocked — WITH CHECK false"]
    BI[branches]
    OI[organizations]
    SMI[staff_members]
    SBAI[staff_branch_assignments]
    ASI[app_settings]
  end

  subgraph rpc_only["Mutations via SECURITY DEFINER RPC — M4"]
    RPC[bootstrap_* / create_staff_account]
  end

  blocked -.->|use instead| RPC
```

---

## End-to-end installation lifecycle

```mermaid
stateDiagram-v2
  [*] --> Seeded: M5 seed runs
  Seeded --> NoOrg: bootstrap admin exists, zero organizations
  NoOrg --> HasOrg: bootstrap_create_organization
  HasOrg --> HasBranch: bootstrap_create_branch
  HasBranch --> Provisioned: create_staff_account
  Provisioned --> Running: normal login + RLS

  note right of NoOrg
    JWT setup_required=true
    organization_id null
  end note

  note right of Running
    JWT full claims
    RLS org + branch scoped
  end note
```

```mermaid
flowchart TB
  Start([Fresh DB after all migrations])
  Start --> S1[M5: roles_permissions seeded]
  S1 --> S2[M5: bootstrap admin in auth.users + staff_members]
  S2 --> S3[User logs in]
  S3 --> S4[GoTrue → get_custom_claims → build_staff_claims]
  S4 --> S5{organization exists?}
  S5 -->|no| S6[setup_required JWT — bootstrap path]
  S5 -->|yes| S7[Full org/branch JWT]
  S6 --> S8[bootstrap_create_organization RPC]
  S8 --> S9[bootstrap_create_branch RPC]
  S9 --> S10[Re-login or refresh token for new claims]
  S7 --> S11[create_staff_account / admin_reset_staff_password]
  S10 --> S11
  S11 --> S12[PostgREST reads/writes under RLS]
```

---

## Bootstrap create organization (RPC)

```mermaid
flowchart TD
  A([bootstrap_create_organization]) --> B[assert_bootstrap_admin]
  B --> C{organization_exists?}
  C -->|yes| E1[rpc_error ORG_ALREADY_EXISTS]
  C -->|no| D{name valid?}
  D -->|no| E2[rpc_error INVALID_INPUT]
  D -->|yes| F[INSERT organizations]
  F --> G[INSERT audit_log organization.bootstrap_create]
  G --> H[rpc_success organization_id]

  B -.->|NOT_BOOTSTRAP_ADMIN| E3[rpc_error NOT_BOOTSTRAP_ADMIN]
```

---

## Bootstrap create branch (RPC)

```mermaid
flowchart TD
  A([bootstrap_create_branch]) --> B[assert_bootstrap_admin → v_staff]
  B --> C{org exists & not deleted?}
  C -->|no| E1[rpc_error ORG_NOT_FOUND]
  C -->|yes| D{name valid?}
  D -->|no| E2[rpc_error INVALID_INPUT]
  D -->|yes| F{first branch for org?}
  F --> G[INSERT branches]
  G --> H{first branch?}
  H -->|yes| I[INSERT staff_branch_assignments primary for bootstrap admin]
  H -->|no| J[skip assignment]
  I --> K[INSERT audit_log branch.bootstrap_create]
  J --> K
  K --> L[rpc_success branch_id]

  B -.->|NOT_BOOTSTRAP_ADMIN| E3[rpc_error NOT_BOOTSTRAP_ADMIN]
```

---

## Create staff account (RPC)

```mermaid
flowchart TD
  A([create_staff_account]) --> B[assert_owner_or_administrator]
  B --> C{organization_exists?}
  C -->|no| E1[rpc_error ORG_SETUP_INCOMPLETE]
  C -->|yes| D{branch_ids & fields valid?}
  D -->|no| E2[rpc_error INVALID_INPUT]
  D -->|yes| R{role = owner?}
  R -->|yes| R1{owner_exists?}
  R1 -->|yes| R2{caller is owner?}
  R2 -->|no| E3[rpc_error FORBIDDEN_OWNER_CREATE]
  R1 -->|no| R3{caller is bootstrap_admin?}
  R3 -->|no| E3
  R -->|no| V[validate branch_ids in org]
  R2 -->|yes| V
  R3 -->|yes| V
  V -->|invalid| E4[rpc_error INVALID_BRANCH]
  V -->|ok| W[create_auth_user → auth.users + identities]
  W --> X[INSERT staff_members]
  X --> Y[FOREACH branch: INSERT staff_branch_assignments]
  Y --> Z[INSERT audit_log staff.create]
  Z --> S[rpc_success staff_member_id + assigned_password]

  W -.->|EMAIL_EXISTS| E5[rpc_error EMAIL_EXISTS]
  B -.->|FORBIDDEN| E6[rpc_error FORBIDDEN]
```

```mermaid
flowchart LR
  create_staff_account --> create_auth_user
  create_auth_user --> crypt["extensions.crypt + gen_salt"]
  create_auth_user --> auth_users[(auth.users)]
  create_auth_user --> auth_id[(auth.identities)]
```

---

## Admin reset staff password (RPC)

```mermaid
flowchart TD
  A([admin_reset_staff_password]) --> B[assert_owner_or_administrator]
  B --> C{password non-empty?}
  C -->|no| E1[rpc_error INVALID_INPUT]
  C -->|yes| D[SELECT target staff_members]
  D -->|not found| E2[rpc_error STAFF_NOT_FOUND]
  D -->|found| F{cross-org via branch assignments?}
  F -->|outside jwt org| E3[rpc_error CROSS_ORG_DENIED]
  F -->|same org| G[UPDATE auth.users encrypted_password]
  G --> H[INSERT audit_log staff.password_reset]
  H --> I[rpc_success assigned_password]

  F --> jwt_organization_id
  B -.->|FORBIDDEN| E4[rpc_error FORBIDDEN]
```

---

## build_staff_claims data dependencies

```mermaid
erDiagram
  auth_users ||--o| staff_members : "auth_user_id"
  staff_members ||--o{ staff_branch_assignments : "staff_member_id"
  staff_branch_assignments }o--|| branches : "branch_id"
  branches }o--|| organizations : "organization_id"
  organizations ||--o| subscription_cache : "organization_id"

  staff_members {
    uuid id
    uuid auth_user_id
    staff_role role
    boolean is_bootstrap_admin
    boolean is_active
  }

  organizations {
    uuid id
    boolean is_deleted
  }

  branches {
    uuid id
    uuid organization_id
    boolean is_active
  }
```

```mermaid
flowchart LR
  build_staff_claims --> staff_members
  build_staff_claims --> organizations
  build_staff_claims --> staff_branch_assignments
  build_staff_claims --> branches
```

---

## Tables touched by RPCs (writes)

```mermaid
flowchart TB
  subgraph bootstrap_org["bootstrap_create_organization"]
    W1[(organizations)]
    W2[(audit_log)]
  end

  subgraph bootstrap_br["bootstrap_create_branch"]
    W3[(branches)]
    W4[(staff_branch_assignments)]
    W5[(audit_log)]
  end

  subgraph create_staff["create_staff_account"]
    W6[(auth.users)]
    W7[(auth.identities)]
    W8[(staff_members)]
    W9[(staff_branch_assignments)]
    W10[(audit_log)]
  end

  subgraph reset_pw["admin_reset_staff_password"]
    W11[(auth.users UPDATE)]
    W12[(audit_log)]
  end
```

---

## Seed migration (M5) — data flow

```mermaid
flowchart TB
  M5[M5 auth_rbac_seed.sql]
  M5 --> RP[INSERT roles_permissions ON CONFLICT UPDATE]
  M5 --> DO[DO block bootstrap admin]

  DO --> AU{auth.users exists?}
  AU -->|no| INS_AU[INSERT auth.users + identities]
  AU -->|yes| SKIP_AU[skip]
  INS_AU --> SM{staff_members exists?}
  SKIP_AU --> SM
  SM -->|no| INS_SM[INSERT staff_members is_bootstrap_admin=true]
  SM -->|yes| SKIP_SM[skip]

  DO --> CRYPT["extensions.crypt + gen_salt"]
```

```mermaid
flowchart LR
  subgraph seed_only["M5 only — no function calls"]
    RP2[roles_permissions rows]
    BA[bootstrap admin fixed UUIDs]
  end
```

---

## Grants and execution surface

```mermaid
flowchart TB
  subgraph authenticated_grants["GRANT EXECUTE — authenticated"]
    G1[bootstrap_create_organization]
    G2[bootstrap_create_branch]
    G3[create_staff_account]
    G4[admin_reset_staff_password]
    G5[get_custom_claims uuid]
  end

  subgraph auth_admin["GRANT EXECUTE — supabase_auth_admin if role exists"]
    G6[get_custom_claims jsonb]
  end

  subgraph no_client_grant["Not granted to clients"]
    NG1[create_auth_user]
    NG2[assert_*]
    NG3[build_staff_claims direct]
    NG4[organization_exists / owner_exists]
  end
```
