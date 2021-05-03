

# Kafka service
resource "aiven_kafka" "kafka-service" {
  project = var.avn_kafka_svc_project_id
  cloud_name = var.avn_kafka_svc_cloud
  plan = var.avn_kafka_svc_plan
  service_name = var.avn_kafka_svc_name
  #maintenance_window_dow = "monday"
  #maintenance_window_time = "10:00:00"

  kafka_user_config {
    kafka_version = var.avn_kafka_svc_version
  }
}

# Kafka connect service
resource "aiven_kafka_connect" "kafka_connect" {
  project = var.avn_kafka_svc_project_id
  cloud_name = var.avn_kafka_svc_cloud
  plan = var.avn_kafka_svc_plan
  service_name = var.avn_kafka_connector_svc_name

  kafka_connect_user_config {
    kafka_connect {
      consumer_isolation_level = "read_committed"
    }

    public_access {
      kafka_connect = true
    }
  }
}

# Kafka connect service integration
resource "aiven_service_integration" "i1" {
  project = var.avn_kafka_svc_project_id
  integration_type = "kafka_connect"
  source_service_name = aiven_kafka.kafka-service.service_name
  destination_service_name = aiven_kafka_connect.kafka_connect.service_name

  kafka_connect_user_config {
    kafka_connect {
      group_id = "connect"
      status_storage_topic = "__connect_status"
      offset_storage_topic = "__connect_offsets"
    }
  }
}

# create Kafka topic
resource "aiven_kafka_topic" "demo-topic" {
  project = var.avn_kafka_svc_project_id
  service_name = var.avn_kafka_svc_name
  topic_name = "demo-topic"
  partitions = 3
  replication = 2
}