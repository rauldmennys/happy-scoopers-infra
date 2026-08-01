# ============================================================
# Módulo de UNA VM para UN estudiante.
# Cada quien lo aplica en SU cuenta Azure for Students.
# Diferencia con ../infra (el del instructor, que crea N VMs):
# aquí no hay for_each ni lista de estudiantes — es una sola
# máquina, un solo estado, una sola persona responsable.
# ============================================================
terraform {
  required_version = ">= 1.6"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.0" }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}
