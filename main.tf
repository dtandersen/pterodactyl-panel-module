resource "null_resource" "ptero" {

  provisioner "file" {
    #source      = "firstboot.sh"
    destination = "/tmp/firstboot.sh"
    content     = "${data.template_file.init.rendered}"
  }

  triggers = {
    template = "${md5(data.template_file.init.rendered)}"
  }

  connection {
    type     = "ssh"
    host     = "${var.ssh_host}"
    user     = "${var.ssh_user}"
    password = "${var.ssh_password}"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/firstboot.sh"
    ]
  }
}

data "template_file" "init" {
  template = "${file("${path.module}/firstboot.sh")}"

  vars {
    DOMAIN = "${var.domain}"
    EMAIL = "${var.email}"

    mysql_root_password = "${var.mysql_root_password}"
    mysql_database = "${var.mysql_database}"
    mysql_user     = "${var.mysql_user}"
    mysql_password = "${var.mysql_password}"

    admin_user     = "${var.admin_user}"
    admin_password = "${var.admin_password}"
    admin_first    = "${var.admin_first}"
    admin_last     = "${var.admin_last}"
  }
}
