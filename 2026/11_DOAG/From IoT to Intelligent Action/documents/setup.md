# Demo environment – setup and checklist

*From IoT Data to Intelligent Action · DOAG K&A in Nuremberg · November 2026*

Related: demo script [demo_nue.md](demo_nue.md) · code and full instructions in [scripts/README.md](../scripts/README.md)

Existing: Oracle Autonomous AI Database 26ai (transaction processing) with APEX. To do: OCI IoT Platform, Private Agent Factory, coding agent with Oracle Skills. Total effort: about one day, plus a dry run.

All OCI resources in **one region** (Frankfurt, `eu-frankfurt-1`). Time stamps in the database are UTC.

**No Python and no laptop process.** The 50 field devices are simulated in the database: the scheduler job `DH_TICK_JOB` generates a reading per twin every 30 seconds, stores it in `DH_TELEMETRY` and posts it to the OCI IoT Platform like a real device (`06b_device_sim.sql`). The IoT Platform shows the twins live in the OCI Console; the database does not read the data back (that would need an OAuth application in an identity domain, see the optional chapter in `scripts/README.md`).

## 1. Autonomous AI Database (30 min)

All commands in SQLcl from the `scripts` folder (session settings: `scripts/login.sql`).

1. As `ADMIN`: `@sql/00a_admin_setup.sql` asks for the demo user (Enter = `GRAPHAI`) and its password (hidden), creates the user if missing and grants (incl. `CREATE PROPERTY GRAPH`, `CREATE JOB`, `CREATE ANY CONTEXT` and `EXECUTE` on `DBMS_CRYPTO` for the encrypted device password). No network ACL is needed: `APEX_WEB_SERVICE` reaches the IoT hosts without one.
2. As `GRAPHAI`: `@sql/00b_check_prereqs.sql`. Look for **"DBMS_OGA OK"**. If not available, Act 3 uses the SQL/PGQ fallbacks (already in the scripts) and Graph Studio.
3. As `GRAPHAI`: `SPOOL log/install.log`, `@sql/00c_install_all.sql`, `SPOOL OFF`. The install asks for the IoT domain short ID, the device password (stored encrypted, shown as `********`) and publish Y/N; press Enter if the IoT Platform is not set up yet. The last queries must show no invalid objects, a health overview (PS-04 WARNING, PS-08 WATCH, SS-09.3 ALARM/WATCH, 5 cold buildings) and the job `DH_TICK_JOB`, still disabled.

## 2. OCI IoT Platform (45 min)

Follow `scripts/README.md`, section **6. Optional: OCI IoT Platform**, 6.1–6.7, all in the OCI Console apart from the twins:

1. Policy `manage iot-family` (if you are not an administrator).
2. IoT domain group `dh-demo-iot-domain-group` → data host.
3. IoT domain `dh-demo-iot-domain` → OCID and **device host**.
4. Vault secret `dh-demo-device-pwd` (the device password for all twins) and the policy for `iotdomain`.
5. Cloud Shell: `WITH_RELATIONSHIPS=1 bash scripts/iot/setup_iot.sh` creates 2 models, 2 adapters, 50 twins (external key = asset id, e.g. `PS-04`) and the `feeds` relationships.
6. In the database: `@sql/01_schema.sql` asks for the domain short ID, the device password (hidden) and publish Y/N; answer Y.
7. Test: `EXEC dh_device_sim.publish_test('PS-04')` → HTTP 202 Accepted, then the twin's *Data* tab in the Console shows the test values. If it stays `{}`, the reason is in `REJECTED_DATA`: Cloud Shell `oci iot domain configure-apex-data-access` (once), then SQL in the IoT domain's APEX workspace (README 6.7). The time stamp needs six decimal places (`.175000Z`).

Last checked 2026-10-28: 50 twins ACTIVE, the job posts all 50 every 30 seconds (`publish: 50 ok, 0 failed`), `HISTORIZED_DATA` grows by 250 per tick, no new rows in `REJECTED_DATA`.

## 3. Start the simulation (5 min)

```sql
EXEC DBMS_SCHEDULER.ENABLE('DH_TICK_JOB')
-- after a minute
SELECT dh_device_sim.status FROM dual;   -- "publish: 50 ok, 0 failed"
SELECT logged_at, step, message FROM dh_job_log ORDER BY log_id DESC FETCH FIRST 10 ROWS ONLY;   -- no rows = no errors
```

Without the IoT Platform (or if it is unreachable): `@sql/iot_publish.sql off` (`on` starts the posts again). The demo keeps running; only the Console view in Act 1 does not update. To remove the twins, adapters and models: `bash scripts/iot/teardown_iot.sh` in Cloud Shell (README 6.8).

## 4. APEX app (45 min)

See `scripts/apex/README.md` (what each page shows) and `scripts/apex/BUILD.md` (prerequisites, Graph Visualization plug-in, Web Credential and Generative AI Service, import of the APEXlang export from `scripts/apex/`). Pages: 1 Home, 2 Network, 3 Incident, 4 Asset, 5 Assistant, 6 Work order, 7 Tasks, 8 Task details, 9 Work orders.

## 5. Private Agent Factory (60 min)

Release **26.10** (October 2026). New in 26.10: Deep NL2SQL (natural-language questions on database data, with Knowledge Space for business context), an Ingestion Service for enterprise content, observability dashboards and trace export, execution of compatible workflows in the Database Agent Engine, and a Python SDK and REST API. For the demo we use the Agent Builder with the Oracle PL/SQL Executor; the trace view helps to show the tool calls in Act 5.

Docs: [Private Agent Factory 26.10 – Get Started](https://docs.oracle.com/en/database/oracle/agent-factory/26.10/paias/database-setup.html#Get-Started-0) · [documentation home](https://docs.oracle.com/en/database/oracle/agent-factory/) · [Marketplace listing](https://marketplace.oracle.com/app/agentfactory) · [LiveLabs workshop](https://livelabs.oracle.com/ords/r/dbpm/livelabs/view-workshop?wid=4336).

### 5.1 Provision from the OCI Marketplace (recommended)

Oracle docs: [Install from OCI Marketplace, 26.10](https://docs.oracle.com/en/database/oracle/agent-factory/26.10/paias/install-oci-marketplace.html#GUID-875084AA-C71A-4AD3-97E2-E8BC6273A4C1) · [Database setup, 26.10](https://docs.oracle.com/en/database/oracle/agent-factory/26.10/paias/database-setup.html#Get-Started-0)

The Marketplace listing is **free of charge**; only the compute instance it creates (and its boot volume) is billed. A Resource Manager stack creates the VM, starts Agent Factory in containers on it, connects it to an Autonomous AI Database as repository and reads the passwords from OCI Vault. The stack does **not** create IAM policies, dynamic groups, vaults, keys, secrets or the database user: prepare these first.

#### 5.1.1 Before you start

**1. Vault and secrets.** Re-use the vault from the IoT setup (chapter 2, step 4, the vault with the secret `dh-demo-device-pwd`); it must be active and have an enabled master encryption key. No second vault is needed. Create these secrets in it (Vault → *Secrets* → *Create secret*, plain text):

| Secret | Content | Rules from the Oracle docs |
|---|---|---|
| `dh-demo-af-admin-pwd` | password of the Agent Factory administrator (web UI) | at least 8 characters, upper- and lowercase letter, digit, special character |
| `dh-demo-af-db-pwd` | password of the repository user `AGENT_FACTORY_APP_USER` (step 3) | no double quote, must not contain the user name |

The stack form takes only **secret OCIDs**, never passwords. Note the two OCIDs.

**2. IAM (tenancy administrator).** If you cannot create groups, dynamic groups or policies yourself, ask your administrator for:
- a **dynamic group** for the Agent Factory VM, e.g. `All {instance.compartment.id = '<compute-compartment-ocid>'}` (best a compartment only for the VM);
- a **deployment policy** for the group that launches the stack: `use marketplace-listings`, `manage orm-stacks`, `manage orm-jobs`, `inspect compartments`, `inspect availability-domains` (tenancy); `read instance-images`, `manage instance-family`, `use volume-family` (compute compartment); `manage virtual-network-family` (network compartment); `read vaults`, `read secret-family` (vault compartment). The exact statements are in the Oracle docs (link above);
- a **runtime policy** so the VM can read the secrets of this vault only:
  ```text
  Allow dynamic-group id <vm-dynamic-group-ocid> to read secret-bundles in compartment id <vault-compartment-ocid>
    where target.vault.id = '<vault-ocid>'
  ```
Allow a few minutes for IAM changes to take effect.

**3. Repository user in the existing Autonomous AI Database.** The repository can be any Oracle AI Database 26ai; it does not have to be the database with the demo data. In this demo it is the same Autonomous AI Database, in its own users. Create the users **before** launching the stack. As `ADMIN`, in SQLcl:

```sql
-- Password for both users, typed hidden (SQLcl); the same value as secret dh-demo-af-db-pwd
ACCEPT password CHAR PROMPT 'Password for AGENT_FACTORY_APP_USER and AAI_RO_AGENT_FACTORY_APP_USER (hidden): ' HIDE

-- Agent Factory repository user (default name in the stack form)
CREATE USER IF NOT EXISTS agent_factory_app_user IDENTIFIED BY "&password"
  DEFAULT TABLESPACE data QUOTA UNLIMITED ON data;
GRANT CREATE SESSION, CREATE TABLE, CREATE SEQUENCE, CREATE TRIGGER, CREATE TYPE,
      CREATE PROCEDURE, CREATE VIEW, CREATE SYNONYM, CREATE JOB TO agent_factory_app_user;
-- additional grants listed for Autonomous AI Database
GRANT SELECT ON SYS.V_$PARAMETER TO agent_factory_app_user;   -- not V$PARAMETER: rejected on ADB
GRANT CTXAPP TO agent_factory_app_user;
GRANT EXECUTE ON CTXSYS.CTX_DDL TO agent_factory_app_user;
GRANT SELECT ON SYS.V_$SQL_PLAN TO agent_factory_app_user;
GRANT EXECUTE ON SYS.DBMS_AQ TO agent_factory_app_user;
GRANT EXECUTE ON SYS.DBMS_AQADM TO agent_factory_app_user;

-- read-only companion user, required by the installer
CREATE USER IF NOT EXISTS aai_ro_agent_factory_app_user IDENTIFIED BY "&password" ACCOUNT UNLOCK;
GRANT CREATE SESSION TO aai_ro_agent_factory_app_user;

UNDEFINE password
```

- Autonomous AI Database uses the tablespace `DATA` (the docs example uses `USERS`, which is for other databases).
- `&password` is a SQLcl substitution variable: `ACCEPT … HIDE` asks for it without showing it, `UNDEFINE` removes it afterwards. Run the block with `SET VERIFY OFF` (as in `login.sql`), so the password is not echoed in the output or a spool file. Both users get the same password, as in the Oracle documentation; it must not contain a double quote (`"`).
- `CREATE USER IF NOT EXISTS` leaves an existing user and its password unchanged; the grants can be run again without error.

Check, connected as `AGENT_FACTORY_APP_USER`:

```sql
SELECT value FROM sys.v_$parameter WHERE name = 'max_string_size';            -- EXTENDED (default on ADB)
SELECT username FROM all_users WHERE username = 'AAI_RO_AGENT_FACTORY_APP_USER';  -- one row
```

**4. Database connectivity: TLS, not wallet.** The Marketplace stack does **not** support wallet-based mutual TLS (mTLS). The existing Autonomous AI Database must therefore accept TLS connections without a wallet: Console → the database → *Network* → *Mutual TLS (mTLS) authentication*: **Not required**. On a public endpoint this needs an **access control list**: add the public IP of the Agent Factory VM (or the CIDR of its subnet). SQLcl, APEX and the demo scripts keep working; a wallet still works for them. If you cannot change these settings, let the stack create a new network and a new Autonomous AI Database, or install manually (5.2).

**5. SSH key and network.**
- SSH key: **ED25519** only (`ssh-keygen -t ed25519`); keep the private key for troubleshooting.
- Network: either an existing VCN in Frankfurt with a public subnet (internet gateway and route rule `0.0.0.0/0` → internet gateway), or let the stack create a new VCN. With an existing VCN you manage the security rules yourself; the stack changes neither route tables, security lists, NSGs nor the database access controls. Ingress for the application port **8080** from your laptop's public IP (`<your-ip>/32`), optionally TCP 22 for SSH. Egress to OCI Vault, the Oracle Container Registry (OCIR), the Oracle Linux package repositories and the database (TLS, port 1521 or 1522).

#### 5.1.2 Launch the stack

1. Open the [Agent Factory listing](https://marketplace.oracle.com/app/agentfactory) → **Get App** → sign in to your tenancy, region **Frankfurt** (`eu-frankfurt-1`).
2. Review the product information → **Launch Stack** → accept the Publisher terms → **Launch Stack**.
3. *Stack Information*: name `dh-demo-agent-factory`, compartment for the stack.
4. *Compute Instance for Private Agent Factory Container*: compute compartment, availability domain, shape (e.g. `VM.Standard.E5.Flex` with 4 OCPUs and 32 GB memory), boot volume **at least 100 GB**, the ED25519 SSH public key.
5. *Network for Compute and Database Connectivity*: **Existing VCN** (compartment, VCN, public compute subnet) and **existing ADB** (compartment, the demo database, not air-gapped). Do not use `10.0.2.0/24` for any subnet: it overlaps the network of the containers (rootless Podman).
6. *Application and database*: Agent Factory database user `AGENT_FACTORY_APP_USER` (default).
7. *Vault*: the vault compartment and the IoT vault; administrator password secret `dh-demo-af-admin-pwd`, database password secret `dh-demo-af-db-pwd`. Agent Factory administrator user name (e.g. your e-mail address or `afadmin`) and the OCIR user name or e-mail address (no auth token needed).
8. Application port `8080`, **allowed client CIDR** = your laptop's public IP `/32`. `0.0.0.0/0` only for a short test.
9. *Advanced settings* (optional): a resource name prefix, e.g. `dh-demo`.
10. **Create** → run the Resource Manager **Plan** job, then the **Apply** job. If Apply fails, the job log names the cause; usually missing permissions, no capacity for the shape, overlapping CIDRs, no access to the vault, or OCIR blocked.
11. When Apply has succeeded: stack → **Outputs** → copy the application URL, format `https://<public-ip>:8080/agentFactory/installation`.

#### 5.1.3 First login and LLM

1. Wait a few minutes after Apply until cloud-init and the containers are ready; the URL then redirects to the login page. Do not restart the VM in the meantime.
2. Open the URL. The certificate is self-signed: check that it is your VM's IP, then *Advanced* → *Proceed* in the browser.
3. Sign in with the administrator user name from the stack form and the password from secret `dh-demo-af-admin-pwd`.
4. **Model Management** → create an LLM configuration (OCI Generative AI, see 5.3) → **Test Connection** → save → set it as the **default** model. Embeddings: by default Agent Factory uses the local `multilingual-e5-base` model; with OCI Generative AI the RAG embedding models are `cohere.embed-v4.0`, `cohere.embed-english-v3.0`, `cohere.embed-multilingual-v3.0` and `cohere.embed-multilingual-light-v3.0`. The demo agent needs no embeddings.

**If the URL does not answer** after Apply: instance details → *Console history*, or via SSH:

```bash
sudo cloud-init status --long
sudo tail -n 200 /var/log/cloud-init-output.log
podman ps -a
podman logs -f oracle-appliedai-selfcontained
```

For an existing VCN and database also check DNS, routes, security rules and the TLS connection from the VM to the database (access control list, mTLS not required).

The setup log shows the cause in plain words: `sudo grep -n -E 'agent-factory|Vault|Error|failed' /var/log/cloud-init-output.log`. Seen in this demo (2026-10-29):

| Log | Cause | Fix |
|---|---|---|
| `Vault retrieval attempt 1/5 failed` … `Unable to retrieve secret from Vault`, then `secret data must be larger than 0` | The VM may not read the secrets: runtime policy missing, or it names the wrong compartment or vault, or the dynamic group does not match the VM. Containers are never started, port 8080 stays closed in the VM firewall, the browser times out. | Create or correct the runtime policy (5.1.1, step 2). Without permission for dynamic groups, a policy on the instance itself also works: `Allow any-user to read secret-bundles in compartment id <vault-compartment-ocid> where ALL {request.principal.type = 'instance', request.principal.id = '<instance-ocid>', target.vault.id = '<vault-ocid>'}`. Then run the setup again (below). |

After fixing the cause, **restart the VM** (Compute → the instance → *Reboot*, or `sudo reboot` via SSH) and wait a few minutes. In this demo (2026-10-29) that was enough: the policy without dynamic group was added, the VM restarted, and Agent Factory came up. If it still does not start, run the whole first-boot setup again on the same VM with `sudo cloud-init clean --logs --reboot` (about 15 minutes; instance OCID and public IP stay the same). Only as a last resort: Resource Manager → the stack → **Destroy**, then **Apply**. That creates a new VM with a new instance OCID and a new public IP, so a policy that names the instance OCID must be adjusted.

**Repository and data sources are separate:** `AGENT_FACTORY_APP_USER` holds Agent Factory's own tables (agents, flows, chats, traces). The data the agents work with is reached through **data sources**, defined inside Agent Factory: each one can point to another database, or to another type of source. In the demo there is one data source, `ADB_DH`, for the schema `GRAPHAI` with the demo data and the `AGENT_*` functions (5.3). `99_teardown.sql` and `test_all.sql` never touch the repository users.

#### 5.1.4 Costs and housekeeping

- Billed: the VM (OCPUs and memory per hour while it runs) and the boot volume. The listing itself is free.
- Between rehearsals stop the instance (Compute → Instances → the Agent Factory VM → **Stop**); a stopped VM costs only its boot volume. Start it 15 minutes before a rehearsal or the session and check the URL. The public IP stays as long as the instance is not terminated; for safety use a reserved public IP.
- The VM is yours to operate: OS patches, certificates and access controls are not managed by Oracle. Before any production use, replace the self-signed certificate.
- After the conference: Resource Manager → the stack → **Destroy** removes what the stack created (not the database user, the secrets or the policies).

### 5.2 Alternative: manual install on your own VM

OCI Compute VM, Oracle Linux, 4 OCPU / 32 GB RAM, 100 GB boot volume, public subnet with ingress 8080 from your laptop IP only. Install Podman and Podman Compose, download the kit from the [download page](https://www.oracle.com/database/technologies/private-agent-factory-downloads.html), run the **Quickstart** (local 26ai Free as repository). Production mode would use your own Oracle AI Database as repository (`max_string_size = EXTENDED`).

### 5.3 Configure Agent Factory for the demo

1. **Model Management** → add OCI Generative AI (API key of your OCI user, or instance principal if the VM is in a dynamic group with a policy for `generative-ai-family`), region Frankfurt, a chat model with tool calling. In this demo: `openai.gpt-oss-120b` (2026-10-29). *Test Connection* → save → set as default. The model parameters (temperature etc.) are not set here but per agent in the **Agent Builder**, on the Agent node (see `scripts/README.md`, section 8.2). An embedding model is only needed for the Knowledge Agent.
2. **Data source** → Oracle Database, name `ADB_DH`: connection to the Autonomous AI Database (TLS connection string of service `<db>_low`, or the wallet if the data source dialog offers it), user **`GRAPHAI`** (not the repository user). Test the connection.
3. Optional: **SMTP** (only if the *Morning Briefing* sends an email): *Hostname*, *Port*, *From Email*, *Username*, *Password* of a mail server the VM can reach, for example your provider's submission server on port 587 with an app password. Saving does not send a test mail; the first run of the flow is the test. Without SMTP the briefing is shown in Chat Output only, or goes to a Slack Webhook.
4. Build the two flows from `scripts/README.md`, sections 8.2 and 8.3 (*Heat Network Ops Agent* and *Morning Briefing*), save them, run the six demo prompts and the briefing test. Check that the Oracle PL/SQL Executor returns the full JSON of the `AGENT_*` functions (they return CLOBs); the `v$sql` check in section 8.2 shows which functions were called.
5. APEX page 5 *Assistant* is not part of Agent Factory: it is an APEX AI Agent with the same `AGENT_*` functions as tools (`scripts/apex/BUILD.md`, sections 9 and 10).

## 6. Coding agent with Oracle Skills (15 min)

See `scripts/README.md`, section 9: Oracle Skills `db` plugin, SQLcl saved connection `dh_demo`, `claude mcp add sqlcl -- sql -mcp`.

## Run of show – the day before and one hour before

| When | Check |
|---|---|
| Day before | `@sql/test_all.sql`: all checks PASS. Nuremberg network loaded (`SELECT value FROM dh_config WHERE name = 'CITY'` returns `NUE`); 50 twins in the OCI Console; `EXEC dh_device_sim.publish_test('PS-04')` returns HTTP 2xx |
| Day before | IoT twins named for Nuremberg: the Console shows e.g. *PS-04 Pump station Galgenhof*; if not, run `bash scripts/iot/setup_iot.sh` in Cloud Shell |
| Day before | Record fallback videos of Acts 1–5 (screen capture, 1080p) into a local folder outside the repository |
| 60 min | `@sql/demo_state.sql base` (reset, history ends "now", job started; ends with 5 cold buildings) |
| 60 min | Wait 2 minutes, `SELECT dh_device_sim.status FROM dual;` ("publish: 50 ok") |
| 60 min | `@sql/check_consistency.sql`: all checks PASS (job running, health in sync, no orphaned work orders, workflows or tasks) |
| 45 min | APEX page 2 (*Network*) shows PS-04 orange (WARNING) or magenta (WATCH), PS-08 magenta, Laufamholz red (stuck sensor SS-09.3), nothing else red |
| 45 min | Agent Factory: prompt 1 answers; delete test work orders (`DELETE FROM dh_work_orders WHERE created_by = 'AI_AGENT' AND workflow_id IS NULL; COMMIT;`) |
| 45 min | Agent Factory: run *Morning Briefing* once in the Playground and keep the result open for Act 4 (with Email Output: the email in the inbox) |
| 30 min | Browser tabs in order: OCI Console (IoT twin PS-04), SQL worksheet (`demo_act2_graph_queries.sql`), APEX page 2 (*Network*), APEX page 3 (*Incident*), Agent Factory chat, VS Code with coding agent. Zoom 125 %, dark themes. APEX signed in as `GRAPHAI` (the workflow tasks of Act 5 go to the user who starts the workflow); page 7 *Tasks* empty, page 9 *Work orders* without open work orders of earlier rehearsals |
| 30 min | Phone hotspot ready for the browser. The data flow runs in OCI and does not depend on the venue Wi-Fi |
| Act 0 | `EXEC dh_device_sim.trip('PS-04')` in the SQL worksheet (≈ 2 min before the root-cause query): spike at the next tick, stopped at the one after |
| After | `@sql/stop_tick_job.sql` (waits for a running tick), stop the Agent Factory VM |
