output "acr_id" {
  value = module.acr.acr_id
}

output "acr_login_server" {
  value = module.acr.acr_login_server
}

output "acr_admin_username" {
  value     = module.acr.acr_admin_username
  sensitive = true
}

output "acr_admin_password" {
  value     = module.acr.acr_admin_password
  sensitive = true
}
