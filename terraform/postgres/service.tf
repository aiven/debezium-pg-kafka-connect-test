
# Postgres 
resource "aiven_service" "avn-us-pg" {
  project      = var.avn_pg_svc_project_id
  cloud_name   = var.avn_pg_svc_cloud
  plan         = var.avn_pg_svc_plan
  service_name = var.avn_pg_svc_name
  service_type = "pg"
  maintenance_window_dow = var.avn_pg_svc_window_dow
  maintenance_window_time = var.avn_pg_svc_window_time

  pg_user_config {
    pg {
        idle_in_transaction_session_timeout = 900
    }
    pg_version = "10"
  }
}




