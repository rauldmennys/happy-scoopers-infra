# Happy Scoopers — Infraestructura del Laboratorio

Crea **tu propia máquina virtual** en Azure con Terraform, ya lista con
todo el stack (PostgreSQL, dlt, dbt, Dagster, Metabase, terminal web).

> Este repo es **solo la infraestructura**. Tu trabajo de datos (los
> modelos dbt) vive en tu fork de **`happy-scoopers-lab`**, que esta VM
> clona sola al arrancar.

---

## Antes de empezar (una vez)

1. **Cuenta gratis**: Azure for Students (`azure.microsoft.com/free/students`).
2. **Herramientas**:
   ```bash
   curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash   # Azure CLI
   sudo apt install -y terraform git                        # Terraform + git
   ls ~/.ssh/id_rsa.pub || ssh-keygen -t rsa -b 4096        # llave SSH
   ```
3. **Forkea el repo del laboratorio** `happy-scoopers-lab` en GitHub y
   copia la URL de **tu** fork. Esa URL es la que pondrás en `repo_url`.

---

## Crear tu VM

```bash
az login
az account show --query id -o tsv        # copia tu subscription_id

git clone https://github.com/<INSTRUCTOR>/happy-scoopers-infra.git
cd happy-scoopers-infra
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars                     # rellena con TUS datos
```

En `terraform.tfvars`, `repo_url` debe ser **tu fork del lab**:
```hcl
repo_url = "https://github.com/TU-USUARIO/happy-scoopers-lab.git"
```

```bash
terraform init
terraform plan       # revisa lo que va a crear
terraform apply      # 'yes' — ~3 min + ~5 de arranque de la VM
terraform output mi_laboratorio
```

---

## Qué hace la VM al arrancar (sola)

- Clona **tu fork del lab** en `/opt/happy-scoopers`
- Instala los paquetes de dbt (`dbt deps`)
- Levanta todos los contenedores (`docker compose up -d`)

**No corre el pipeline.** Eso lo haces tú — es la clase:

```bash
# entra por la terminal web: https://<tu-fqdn>/terminal
cd /opt/happy-scoopers && source .venv/bin/activate
make el-full && make dbt-build
```

---

## El ciclo de cada clase

| Momento | Comando |
|---|---|
| Empezar (si estaba apagada) | `az vm start -g dw-<nombre>-rg -n dw-<nombre>` |
| Trabajar | por la terminal web; `git push` al terminar cada lab |
| Terminar la clase | `az vm deallocate -g dw-<nombre>-rg -n dw-<nombre>` |
| Fin del curso | `terraform destroy` |

**Regla de oro:** si no hiciste `git push` en tu fork del lab, tu trabajo
solo existe en la VM — y la VM es desechable.
