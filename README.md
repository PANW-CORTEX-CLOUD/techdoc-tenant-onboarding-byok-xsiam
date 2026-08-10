# Bring your own keys (BYOK)

First-time walkthrough for encrypting your Cortex tenant with a key **you** create and control.  
You work in Cortex Gateway and on your computer.

> **Single source of truth:** this `README.md` file.  
> Optional styled viewer: [`README.html`](./README.html) (renders this Markdown — serve locally with `python3 -m http.server 8765`).

**Start here (Palo Alto Networks):**  
[Bring your own keys](https://cortex-docs.paloaltonetworks.com/cortex-xsiam/onboard-cortex-xsiam/deployment-steps/activate-cortex-xsiam/bring-your-own-keys) ·
[Activate Cortex XSIAM](https://cortex-docs.paloaltonetworks.com/gateway-guide/activate-a-tenant/activate-cortex-xsiam-tenant) ·
[Cortex XSIAM onboarding checklist](https://docs-cortex.paloaltonetworks.com/r/Cortex-XSIAM/Cortex-XSIAM-3.x-Documentation/Cortex-XSIAM-onboarding-checklist)

## What this means for you

With BYOK, Cortex still hosts your tenant — but the master encryption key comes from you.

Your tenant needs encryption for two areas: the **Data lake** and other **Services**.  
You can use **one** key for both, or create **two** different keys. Most customers start with one shared key.

> [!NOTE]
> You create the secret **32-byte target key**. Cortex Gateway gives you temporary **wrapping keys** (`.pem` files). Wrapping keys only protect your secret during upload — they are **not** your BYOK key.  
> Details: [Bring your own keys — architecture & setup](https://cortex-docs.paloaltonetworks.com/cortex-xsiam/onboard-cortex-xsiam/deployment-steps/activate-cortex-xsiam/bring-your-own-keys)

| Item | Who | What to do |
| --- | --- | --- |
| Target key (`targetkey`) | **You** | Create once, store safely. Never upload this file unwrapped. |
| Wrapping keys (`.pem`) | **Gateway** | Download for Data lake and Services. Valid up to 3 days. |
| Wrapped key files | **Upload** | Created by the helper script. Upload these in Gateway. |

## Process overview

```mermaid
flowchart TB
  A["Start in Cortex Gateway<br/>choose BYOK"]
  B["Create your 32-byte<br/>target key"]
  C1["Download Data lake<br/>wrapping key"]
  C2["Download Services<br/>wrapping key"]
  D1["Wrap for Data lake"]
  D2["Wrap for Services"]
  E["Upload both files<br/>Complete Activation"]
  A --> B
  B --> D1
  B --> D2
  C1 --> D1
  C2 --> D2
  D1 --> E
  D2 --> E
  classDef you fill:#e8faf0,stroke:#00a452,stroke-width:2px,color:#1c1c24
  classDef gateway fill:#f0f1ff,stroke:#7c74de,stroke-width:2px,color:#1c1c24
  classDef upload fill:#ffffff,stroke:#1c1c24,stroke-width:2px,color:#1c1c24
  class B you
  class A,C1,C2 gateway
  class D1,D2,E upload
```

## Files in this repo

| File | Purpose |
| --- | --- |
| [`run-byok.sh`](./run-byok.sh) | Launcher |
| [`byok-wrap-keys.sh`](./byok-wrap-keys.sh) | Generate / wrap keys |
| [`README.html`](./README.html) | Viewer that renders this `README.md` (SSOT) |
| [`.gitignore`](./.gitignore) | Blocks key material from git |

```bash
chmod +x byok-wrap-keys.sh run-byok.sh
```

## Step-by-step

### 1. Start BYOK in Cortex Gateway

Sign in to Cortex Gateway and activate your tenant.  
Under **Advanced**, select **BYOK (Bring Your Own Keys)**, then **Create Tenant and Set Up Keys**.

Initialization can take a few minutes. If you pause, continue later with **Set Up Encryption Keys** next to the tenant.

**Learn more (Palo Alto Networks):**

- [Activate a tenant (Gateway guide)](https://cortex-docs.paloaltonetworks.com/gateway-guide/activate-a-tenant)
- [Activate Cortex XSIAM tenant](https://cortex-docs.paloaltonetworks.com/gateway-guide/activate-a-tenant/activate-cortex-xsiam-tenant)
- [Activate Cortex XSIAM — Administrator Guide](https://docs-cortex.paloaltonetworks.com/r/Cortex-XSIAM/Cortex-XSIAM-3.x-Documentation/Activate-Cortex-XSIAM)
- [Cortex XSIAM supported regions](https://cortex-docs.paloaltonetworks.com/cortex-xsiam/onboard-cortex-xsiam/deployment-steps/activate-cortex-xsiam/cortex-xsiam-supported-regions)
- [Set up new tenant with BYOK](https://cortex-docs.paloaltonetworks.com/cortex-xsiam/onboard-cortex-xsiam/deployment-steps/activate-cortex-xsiam/bring-your-own-keys)

### 2. Create your 32-byte target key

On your computer:

```bash
./run-byok.sh generate targetkey
```

In Gateway, select **I have a 32-byte symmetric encryption key ready** and continue.

> [!CAUTION]
> Treat `targetkey` like a root secret. Back it up offline. Do not email it, store it in git, or upload it unwrapped.

**Learn more:** [BYOK setup — Generate Key](https://cortex-docs.paloaltonetworks.com/cortex-xsiam/onboard-cortex-xsiam/deployment-steps/activate-cortex-xsiam/bring-your-own-keys) (32-byte symmetric encryption key requirement)

### 3. Download wrapping keys

On the **Wrap & Upload** screen, repeat for **Data lake** and **Services**:

1. Choose import method `RSA_OAEP_3072_SHA256_AES_256` (default)
2. Download the wrapping `.pem`

> [!NOTE]
> Wrapping keys expire after three days. If they expire, download new ones before wrapping.

**Learn more:**

- [Wrap & Upload — import methods and wrapping key](https://cortex-docs.paloaltonetworks.com/cortex-xsiam/onboard-cortex-xsiam/deployment-steps/activate-cortex-xsiam/bring-your-own-keys)
- Same topic in the Administrator Guide: [Bring your own keys](https://docs-cortex.paloaltonetworks.com/r/Cortex-XSIAM/Cortex-XSIAM-3.x-Documentation/Bring-your-own-keys)

### 4. Wrap your target key

Place both `.pem` files next to the script, then run:

```bash
./run-byok.sh wrap-both \
  datalake_wrapping_key.pem \
  services_wrapping_key.pem \
  targetkey \
  ./out
```

Output:

- `out/datalakewrappedkey`
- `out/serviceswrappedkey`

The default import method (`RSA_OAEP_*_SHA256_AES_256`) needs patched OpenSSL at `$HOME/local/bin/openssl.sh` (or set `OPENSSL_SH`).

**Learn more:**

- OpenSSL wrap procedure in PANW docs: [Bring your own keys — wrap procedure](https://cortex-docs.paloaltonetworks.com/cortex-xsiam/onboard-cortex-xsiam/deployment-steps/activate-cortex-xsiam/bring-your-own-keys)
- Linked from PANW docs: [Configuring OpenSSL for manual key wrapping (Google Cloud)](https://docs.cloud.google.com/kms/docs/configuring-openssl-for-manual-key-wrapping)
- Linked from PANW docs: [Wrapping a key using OpenSSL (Google Cloud)](https://docs.cloud.google.com/kms/docs/wrapping-a-key)

### 5. Upload and complete activation

Upload the Data lake wrapped file, then the Services wrapped file.  
Click **Complete Activation**.

Your key becomes the primary encryption key for newly generated tenant data.

**Learn more:**

- [Complete Activation / key import](https://cortex-docs.paloaltonetworks.com/cortex-xsiam/onboard-cortex-xsiam/deployment-steps/activate-cortex-xsiam/bring-your-own-keys)
- Later operations (rotate / disable): same page — *Rotate encryption keys* and *Disable encryption keys*
- Broader onboarding context: [Cortex XSIAM onboarding checklist](https://docs-cortex.paloaltonetworks.com/r/Cortex-XSIAM/Cortex-XSIAM-3.x-Documentation/Cortex-XSIAM-onboarding-checklist)

## Checklist

- [ ] BYOK selected during tenant activation
- [ ] 32-byte `targetkey` created and stored securely
- [ ] Data lake wrapping `.pem` downloaded
- [ ] Services wrapping `.pem` downloaded
- [ ] `wrap-both` completed successfully
- [ ] Both wrapped files uploaded
- [ ] Complete Activation selected

## Helper commands

```bash
./run-byok.sh generate [targetkey]
./run-byok.sh wrap <gateway_wrapping.pem> <targetkey> <wrapped_out>
./run-byok.sh wrap-both <datalake.pem> <services.pem> <targetkey> [out_dir]
```

> [!NOTE]
> File names such as `targetkey` and `datalake_wrapping_key.pem` are helper-script conventions. Use the wrapping files you download from Gateway, even if their names differ.

## Further reading (Palo Alto Networks)

| Topic | Documentation |
| --- | --- |
| BYOK overview, wrap, rotate, disable | [Bring your own keys](https://cortex-docs.paloaltonetworks.com/cortex-xsiam/onboard-cortex-xsiam/deployment-steps/activate-cortex-xsiam/bring-your-own-keys) |
| BYOK (Administrator Guide mirror) | [Bring your own keys — Cortex XSIAM 3.x](https://docs-cortex.paloaltonetworks.com/r/Cortex-XSIAM/Cortex-XSIAM-3.x-Documentation/Bring-your-own-keys) |
| Tenant activation & encryption method | [Activate Cortex XSIAM](https://docs-cortex.paloaltonetworks.com/r/Cortex-XSIAM/Cortex-XSIAM-3.x-Documentation/Activate-Cortex-XSIAM) |
| Activate XSIAM from Gateway | [Activate Cortex XSIAM tenant](https://cortex-docs.paloaltonetworks.com/gateway-guide/activate-a-tenant/activate-cortex-xsiam-tenant) |
| Gateway activation hub | [Activate a tenant](https://cortex-docs.paloaltonetworks.com/gateway-guide/activate-a-tenant) |
| Deployment checklist (includes BYOK) | [Cortex XSIAM onboarding checklist](https://docs-cortex.paloaltonetworks.com/r/Cortex-XSIAM/Cortex-XSIAM-3.x-Documentation/Cortex-XSIAM-onboarding-checklist) |
| Hosting regions | [Cortex XSIAM supported regions](https://cortex-docs.paloaltonetworks.com/cortex-xsiam/onboard-cortex-xsiam/deployment-steps/activate-cortex-xsiam/cortex-xsiam-supported-regions) |
