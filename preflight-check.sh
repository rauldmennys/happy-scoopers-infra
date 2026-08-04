#!/usr/bin/env bash
# preflight-check.sh - Happy Scoopers DW lab
# Local toolchain pre-flight for the "student 0" Azure deployment path.
# Run this on YOUR machine (laptop / WSL / macOS) BEFORE `terraform apply`.
# Mirrors the ELT pipeline's PASS / WARN / ERROR reporting style.

set -uo pipefail

readonly PREFLIGHT_VERSION="1.2.0"   # 1.2.0 = DRY: read sku/region from tf files
# 1.1.0 = Location(ERROR)/Zone(WARN) split

# ---- Config -----------------------------------------------------------------
: "${MIN_TF_VERSION:=1.5.0}"      # bump to your required_version
: "${SSH_PUBKEY:=}"               # leave empty to auto-detect ~/.ssh/*.pub

# Resolve region + SKU from what Terraform will actually deploy, so the check
# never drifts from the config. Priority:
#   1. explicit env var (AZ_REGION=... VM_SKU=...)  -> probe an arbitrary value
#   2. terraform.tfvars                             -> what `apply` will use
#   3. variables.tf default                         -> what a student inherits
#   4. hardcoded fallback
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="${INFRA_DIR:-$SCRIPT_DIR}"
TFVARS="$INFRA_DIR/terraform.tfvars"
VARSFILE="$INFRA_DIR/variables.tf"

tfvars_get() {  # <file> <key> -> value of `key = "value"`
  [ -f "$1" ] || return 1
  sed -n -E "s/^[[:space:]]*$2[[:space:]]*=[[:space:]]*\"([^\"]*)\".*/\1/p" "$1" | head -n1
}
vardefault_get() {  # <file> <varname> -> default of that variable block
  [ -f "$1" ] || return 1
  awk -v want="$2" '
    /^variable[[:space:]]+"/ { name=$0; sub(/^variable[[:space:]]+"/,"",name); sub(/".*/,"",name); inblock=(name==want) }
    inblock && /default[[:space:]]*=/ { l=$0; sub(/.*default[[:space:]]*=[[:space:]]*"/,"",l); sub(/".*/,"",l); print l; exit }
  ' "$1"
}
resolve() {  # <current_env> <tf_key> <fallback> -> "<source>\t<value>"
  local cur="$1" key="$2" fb="$3" v=""
  [ -n "$cur" ] && { printf 'env\t%s' "$cur"; return; }
  v=$(tfvars_get "$TFVARS" "$key")     && [ -n "$v" ] && { printf 'terraform.tfvars\t%s' "$v"; return; }
  v=$(vardefault_get "$VARSFILE" "$key") && [ -n "$v" ] && { printf 'variables.tf\t%s' "$v"; return; }
  printf 'fallback\t%s' "$fb"
}
IFS=$'\t' read -r region_src AZ_REGION < <(resolve "${AZ_REGION:-}" location "westus3")
IFS=$'\t' read -r vm_src     VM_SKU    < <(resolve "${VM_SKU:-}"    vm_size  "Standard_B2s_v2")
# -----------------------------------------------------------------------------

pass=0; warn=0; err=0
if [ -t 1 ]; then
  green=$'\e[32m'; yellow=$'\e[33m'; red=$'\e[31m'; dim=$'\e[2m'; rst=$'\e[0m'
else
  green=""; yellow=""; red=""; dim=""; rst=""
fi
ok()   { printf "  %sPASS%s   %s\n" "$green"  "$rst" "$1"; pass=$((pass+1)); }
wn()   { printf "  %sWARN%s   %s\n" "$yellow" "$rst" "$1"; warn=$((warn+1)); }
bad()  { printf "  %sERROR%s  %s\n" "$red"    "$rst" "$1"; err=$((err+1)); }
note() { printf "         %s%s%s\n" "$dim" "$1" "$rst"; }

# need_ver <current> <minimum> -> success if current >= minimum
need_ver() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]; }

echo "Happy Scoopers DW - local pre-flight v${PREFLIGHT_VERSION}"
echo "OS: $(uname -srm)"
echo "region: ${AZ_REGION} (${region_src})   sku: ${VM_SKU} (${vm_src})"
echo

# --- 1) git ------------------------------------------------------------------
if command -v git >/dev/null 2>&1; then
  ok "git present ($(git --version | awk '{print $3}'))"
else
  bad "git not found - install git first"
fi

# --- 2) Azure CLI ------------------------------------------------------------
have_az=0
if command -v az >/dev/null 2>&1; then
  have_az=1
  azv=$(az version --query '"azure-cli"' -o tsv 2>/dev/null)
  ok "az present (${azv:-unknown})"
else
  bad "az (Azure CLI) not found - https://aka.ms/InstallAzureCLI"
fi

# --- 3) Terraform ------------------------------------------------------------
if command -v terraform >/dev/null 2>&1; then
  tfv=$(terraform version -json 2>/dev/null | grep -o '"terraform_version":"[^"]*"' | cut -d'"' -f4)
  [ -z "${tfv:-}" ] && tfv=$(terraform version | awk 'NR==1{gsub(/v/,"",$2);print $2}')
  if need_ver "${tfv:-0}" "$MIN_TF_VERSION"; then
    ok "terraform present ($tfv >= $MIN_TF_VERSION)"
  else
    wn "terraform ${tfv:-unknown} is older than recommended $MIN_TF_VERSION"
    note "old TF can fail 'terraform init' against a pinned required_version"
  fi
else
  bad "terraform not found - https://developer.hashicorp.com/terraform/install"
fi

# --- 4) SSH public key -------------------------------------------------------
keyfile=""
if [ -n "$SSH_PUBKEY" ] && [ -f "$SSH_PUBKEY" ]; then
  keyfile="$SSH_PUBKEY"
else
  for k in "$HOME"/.ssh/id_ed25519.pub "$HOME"/.ssh/id_rsa.pub; do
    [ -f "$k" ] && { keyfile="$k"; break; }
  done
fi
if [ -n "$keyfile" ]; then
  ok "SSH public key found ($keyfile)"
  note "set this path as ssh_public_key_path in terraform.tfvars if required"
else
  bad "no SSH public key in ~/.ssh - generate one:"
  note "ssh-keygen -t ed25519 -C 'happy-scoopers'"
fi

# --- Azure session checks (only if az is available) --------------------------
if [ "$have_az" -eq 1 ]; then
  echo
  echo "Azure session:"

  if acct=$(az account show -o json 2>/dev/null); then
    sub_name=$(printf '%s' "$acct" | grep -o '"name":[^,]*' | head -n1 | cut -d'"' -f4)
    tenant=$(printf '%s'   "$acct" | grep -o '"tenantId":[^,]*'  | head -n1 | cut -d'"' -f4)
    ok "logged in - subscription: ${sub_name:-?}"
    note "tenant: ${tenant:-?}"

    case "$sub_name" in
      *[Ss]tudent*) : ;;
      *) wn "subscription name has no 'Student' - confirm this is Azure for Students, not a personal account" ;;
    esac

    nsubs=$(az account list --query "length(@)" -o tsv 2>/dev/null || echo 0)
    if [ "${nsubs:-0}" -gt 1 ]; then
      wn "$nsubs subscriptions visible - make sure the active one is correct"
      note "az account set --subscription '<Azure for Students>'"
    fi

    # --- resource providers ---
    echo
    echo "Resource providers:"
    for p in Microsoft.Compute Microsoft.Network Microsoft.Storage; do
      st=$(az provider show -n "$p" --query registrationState -o tsv 2>/dev/null)
      if [ "$st" = "Registered" ]; then
        ok "$p registered"
      else
        wn "$p is '${st:-unknown}' - register it:"
        note "az provider register -n $p"
      fi
    done

    # --- SKU availability + regional quota ---
    echo
    echo "Compute capacity in ${AZ_REGION}:"
    # Location restriction = not deployable at all (ERROR).
    # Zone restriction only = deployable regionally without a pinned zone (WARN).
    skucount=$(az vm list-skus -l "$AZ_REGION" --all \
                --query "length([?name=='${VM_SKU}'])" -o tsv 2>/dev/null)
    if [ "${skucount:-0}" -eq 0 ]; then
      bad "${VM_SKU} is not offered in ${AZ_REGION}"
      note "pick another region or SKU in terraform.tfvars"
    else
      rtypes=$(az vm list-skus -l "$AZ_REGION" --all \
                --query "[?name=='${VM_SKU}'].restrictions[].type" -o tsv 2>/dev/null)
      if printf '%s\n' "$rtypes" | grep -qx "Location"; then
        bad "${VM_SKU} is NotAvailableForSubscription in ${AZ_REGION} (Location restriction)"
        note "pick another region or SKU in terraform.tfvars"
      elif printf '%s\n' "$rtypes" | grep -qx "Zone"; then
        wn "${VM_SKU} available in ${AZ_REGION} but restricted in some zones"
        note "deploy regionally - do NOT pin 'zone' in azurerm_linux_virtual_machine"
      else
        ok "${VM_SKU} available in ${AZ_REGION} (no restrictions)"
      fi
    fi

    usage=$(az vm list-usage -l "$AZ_REGION" -o json 2>/dev/null)
    tot=$(printf '%s' "$usage" | grep -A3 '"Total Regional vCPUs"' | grep -o '"currentValue": *[0-9]*\|"limit": *[0-9]*' | grep -o '[0-9]*' | tr '\n' '/' | sed 's:/$::')
    if [ -n "$tot" ]; then
      cur=${tot%%/*}; lim=${tot##*/}
      if [ "${lim:-0}" -eq 0 ]; then
        bad "Total Regional vCPU quota is 0 in ${AZ_REGION} - apply will fail"
        note "request quota or switch region"
      else
        ok "regional vCPU quota ${cur:-?}/${lim:-?} used"
      fi
    fi
  else
    bad "not logged in - run: az login   (headless/ttyd: az login --use-device-code)"
  fi
fi

# --- summary -----------------------------------------------------------------
echo
printf "Result: %sPASS=%d%s %sWARN=%d%s %sERROR=%d%s\n" \
  "$green" "$pass" "$rst" "$yellow" "$warn" "$rst" "$red" "$err" "$rst"
[ "$err" -eq 0 ] && echo "Ready for: git clone happy-scoopers-infra && terraform apply" \
                 || echo "Resolve ERRORs above before terraform apply."
exit "$err"
