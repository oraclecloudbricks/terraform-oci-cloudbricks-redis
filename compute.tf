# Copyright (c) 2021 Oracle and/or its affiliates.
# All rights reserved. The Universal Permissive License (UPL), Version 1.0 as shown at http://oss.oracle.com/licenses/upl
# compute.tf
#
# Purpose: The following script defines the declaration of computes needed for the Redis deployment
# Registry: https://registry.terraform.io/providers/hashicorp/oci/latest/docs/resources/core_instance
#           https://registry.terraform.io/providers/hashicorp/oci/latest/docs/resources/core_volume_backup_policy_assignment


resource "tls_private_key" "ssh_key_pair" {
  algorithm = "RSA"
  rsa_bits  = "4096"
}

resource "oci_core_instance" "redis_master" {
  depends_on = [tls_private_key.ssh_key_pair]
  availability_domain = var.redis_master_ad
  fault_domain        = var.redis_master_fd
  compartment_id      = local.compartment_id
  display_name        = var.redis_master_name
  shape               = var.redis_master_shape

  dynamic "shape_config" {
    for_each = local.redis_master_is_flex_shape ? [1] : []
    content {
      ocpus         = var.redis_master_ocpus
      memory_in_gbs = var.redis_master_memory_in_gb
    }
  }

  agent_config {
    plugins_config {
      desired_state = "ENABLED"
      name          = "Bastion"
    }
  }

  create_vnic_details {
    subnet_id        = local.private_subnet_ocid
    display_name     = "primaryvnic"
    assign_public_ip = false
    hostname_label   = var.redis_master_name
    nsg_ids          = local.nsg_id == "" ? [] : [local.nsg_id]
  }

  source_details {
    source_type = "image"
    source_id   = local.base_compute_image_ocid
  }

  connection {
    agent       = false
    host        = self.private_ip
    user        = "opc"
    private_key = tls_private_key.ssh_key_pair.private_key_pem
  }

  metadata = {
    ssh_authorized_keys = local.ssh_authorized_keys
  }
}

resource "oci_core_instance" "redis_replica" {
  depends_on = [tls_private_key.ssh_key_pair]
  count               = var.redis_replica_count
  availability_domain = local.ad_names_list[count.index % var.redis_replica_ad_count]
  fault_domain        = local.fd_names_list[floor(count.index / var.redis_replica_ad_count) % var.redis_replica_fd_count]
  compartment_id      = local.compartment_id
  display_name        = "${var.redis_replica_name}${count.index + 1}"
  shape               = var.redis_replica_shape

  dynamic "shape_config" {
    for_each = local.redis_replica_is_flex_shape ? [1] : []
    content {
      ocpus         = var.redis_replica_ocpus
      memory_in_gbs = var.redis_replica_memory_in_gb
    }
  }

  agent_config {
    plugins_config {
      desired_state = "ENABLED"
      name          = "Bastion"
    }
  }

  create_vnic_details {
    subnet_id        = local.private_subnet_ocid
    display_name     = "primaryvnic"
    assign_public_ip = false
    hostname_label   = "${var.redis_replica_name}${count.index + 1}"
    nsg_ids          = local.nsg_id == "" ? [] : [local.nsg_id]
  }

  source_details {
    source_type = "image"
    source_id   = local.base_compute_image_ocid
  }

  connection {
    agent       = false
    host        = self.private_ip
    user        = "opc"
    private_key = tls_private_key.ssh_key_pair.private_key_pem
  }

  metadata = {
    ssh_authorized_keys = local.ssh_authorized_keys
  }
}


resource "oci_core_volume_backup_policy_assignment" "backup_policy_assignment_redis_master" {
  depends_on = [oci_core_instance.redis_master]
  asset_id   = oci_core_instance.redis_master.boot_volume_id
  policy_id  = local.instance_backup_policy_id
}


resource "oci_core_volume_backup_policy_assignment" "backup_policy_assignment_redis_replica" {
  count      = var.redis_replica_count
  depends_on = [oci_core_instance.redis_replica]
  asset_id   = oci_core_instance.redis_replica[count.index].boot_volume_id
  policy_id  = local.instance_backup_policy_id
}
