#!/bin/bash

set -e
export path=`pwd`
export capath="/opt/.certs"
export docker_data=$(awk -F': ' '/docker_data_dir:/ {print $2}' group_vars/all.yml)
export ansible_log_dir="$path/log"
export ansible_image_url_x86="registry.cn-chengdu.aliyuncs.com/su03/ansible:latest"
export ansible_image_url_arm="registry.cn-chengdu.aliyuncs.com/su03/ansible-arm:latest"
export docker_package_url_x86="https://su-package.oss-cn-chengdu.aliyuncs.com/docker/amd/docker-27.2.0.tgz"
export docker_package_url_arm="https://su-package.oss-cn-chengdu.aliyuncs.com/docker/arm/docker-27.2.0.tgz"
ssh_pass="sulibao"

os_arch=$(uname -m)

if [[ "$os_arch" == "x86_64" ]]; then
    ARCH="x86"
    echo -e "Detected Operating System: $OS, Architecture：X86"
    mkdir -p $ansible_log_dir
elif [[ "$os_arch" == "aarch64" ]]; then
    ARCH="arm64"
    echo -e "Detected Operating System: $OS, Architecture: ARM64"
    mkdir -p $ansible_log_dir
else
    echo -e "Unsupported architecture detected: $os_arch"
    exit 1
fi

function check_arch() {
  if [ -f /etc/redhat-release ]; then
    OS="RedHat"
  elif [ -f /etc/kylin-release ]; then
    OS="kylin"
  else
    echo "Unknow linux distribution."
  fi
  OS_ARCH=$(uname -a)
  if [[ "$OS_ARCH" =~ "x86" ]]
  then
    ARCH="x86"
    echo -e  "The operating system is $OS,the architecture is X86."
  elif [[ "$OS_ARCH" =~ "aarch" ]]
  then
    ARCH="arm64"
    echo -e  "The operating system is $OS,the architecture is Arm."
  fi
}

function check_docker() {
  echo "Make sure docker is installed and running."
  if ! [ -x "$(command -v docker)" ]; then
    echo "docker not find."
    create_docker_group_and_user
    install_docker
  else
    echo "docker exists."
  fi
  if ! systemctl is-active --quiet docker; then
    echo "docker is not running."
    create_docker_group_and_user
    install_docker
  else
    echo "docker is running."
  fi
}

function check_docker_compose() {
  if ! [ -x "$(command -v docker-compose)" ]; then
    echo "docker-compose not find."
    install_docker_compose   
  else
    echo "docker-compose exist."
  fi
}

function create_docker_group_and_user() {
  if ! getent group docker >/dev/null 2>&1; then
    groupadd docker
    echo "docker group created successfully."
  else
    echo "docker group already exists."
  fi
  if ! id -u docker >/dev/null 2>&1; then
    useradd -m -s /bin/bash -g docker docker
    echo "docker user has been created and added to docker group."
  else
    echo "docker user already exists."
  fi
}

function install_docker() {
  echo "Installing docker."
  if [[ "$ARCH" == "x86" ]]
  then
    curl -C - -o $path/packages/docker/x86/docker-27.2.0.tgz $docker_package_url_x86
    cp -v -f $path/packages/docker/x86/docker-27.2.0.tgz $path/roles/docker/files/x86/docker-27.2.0.tgz
  else
    curl -C - -o $path/packages/docker/arm64/docker-27.2.0.tgz $docker_package_url_arm
    cp -v -f $path/packages/docker/arm64/docker-27.2.0.tgz $path/roles/docker/files/arm64/docker-27.2.0.tgz
  fi
  tar axvf $DOCKER_OFFLINE_PACKAGE -C /usr/bin/ --strip-components=1
  cp -v -f $path/packages/docker/docker.service /usr/lib/systemd/system/
  test -d /etc/docker || mkdir -p /etc/docker
  envsubst '$docker_data' < $path/packages/docker/daemon.json > /etc/docker/daemon.json
  systemctl stop firewalld
  systemctl disable firewalld
  systemctl daemon-reload
  systemctl enable docker.service --now
  systemctl restart docker || :
  maxSecond=60
  for i in $(seq 1 $maxSecond); do
    if systemctl is-active --quiet docker; then
      break
    fi
    sleep 1
  done
  if ((i == maxSecond)); then
    echo "Failed to start the docker server, please check the docker start log."
    exit 1
  fi
  echo "Docker has started successfully and the installation is complete."
}

function install_docker_compose {
  echo "Installing docker-compose."
  if [[ "$ARCH" == "x86" ]]
  then
    export DOCKER_COMPOSE_OFFLINE_PACKAGE=$path/packages/docker-compose/x86/docker-compose-linux-x86_64
    cp -v -f $DOCKER_COMPOSE_OFFLINE_PACKAGE /usr/local/bin/docker-compose
  else
    export DOCKER_COMPOSE_OFFLINE_PACKAGE=$path/packages/docker-compose/arm64/docker-compose-linux-aarch64
    cp -v -f $DOCKER_COMPOSE_OFFLINE_PACKAGE /usr/local/bin/docker-compose
  fi
}

function pull_ansible_image() {
  if [[ "$ARCH" == "x86" ]]
  then
    docker pull "$ansible_image_url_x86"
  else
    docker pull "$ansible_image_url_arm"
  fi
  echo -e "Pulled ansible image."
}

function ensure_ansible() {
  echo -e "Checking the status of the ansible."
  if test -z "$(docker ps -a | grep ansible_sulibao)"; then
    echo -e "Ansible is not running, will run."
    run_ansible
  else
    echo -e "Ansible is running, will restart."
    docker restart ansible_sulibao
  fi
}

function run_ansible() {
  echo -e "Installing Ansible container."
  if [[ "$ARCH" == "x86" ]]
  then
    docker run --name ansible_sulibao --network="host" --workdir=$path -d -e LANG=C.UTF-8 -e ssh_password=$ssh_pass --restart=always -v /etc/localtime:/etc/localtime:ro -v ~/.ssh:/root/.ssh -v $path:$path -v "$capath":"$capath" "$ansible_image_url_x86" sleep 31536000
  else
    docker run --name ansible_sulibao --network="host" --workdir=$path -d -e LANG=C.UTF-8 -e ssh_password=$ssh_pass --restart=always -v /etc/localtime:/etc/localtime:ro -v ~/.ssh:/root/.ssh -v $path:$path -v "$capath":"$capath" "$ansible_image_url_arm" sleep 31536000
  fi
  echo -e "Installed Ansible container."
}

function  create_ssh_key(){
  echo -e "Creating sshkey."
  docker exec -i ansible_sulibao /bin/sh -c 'echo -e "y\n"|ssh-keygen -t rsa -N "" -C "deploy@ansible" -f ~/.ssh/id_rsa_ansible -q'
  echo -e "\nCreated sshkey."

}

function copy_ssh_key() {
  echo -e "Copying sshkey."
  docker exec -i ansible_sulibao /bin/sh -c "cd $path && ansible-playbook  ssh-access.yml -e ansible_ssh_pass=$ssh_pass"  
  echo -e "\nCopied sshkey."
}

function install_docker_slave() {
  echo -e "Installing docker for other nodes."
  docker exec -i ansible_sulibao /bin/sh -c "cd $path && ansible-playbook  ./docker.yml"
  echo -e "\nInstalled docker for other nodes."
}

check_arch
check_docker
check_docker_compose
pull_ansible_image
ensure_ansible
create_ssh_key
copy_ssh_key
install_docker_slave
