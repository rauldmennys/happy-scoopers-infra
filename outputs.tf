output "mi_laboratorio" {
  description = "Tus accesos"
  value = {
    web      = "https://${azurerm_public_ip.lab.fqdn}"
    terminal = "https://${azurerm_public_ip.lab.fqdn}/terminal"
    pgadmin  = "https://${azurerm_public_ip.lab.fqdn}/pgadmin"
    metabase = "https://${azurerm_public_ip.lab.fqdn}/metabase"
    ssh      = "ssh azureuser@${azurerm_public_ip.lab.fqdn}"
  }
}
