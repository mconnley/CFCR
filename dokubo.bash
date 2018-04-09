#!/bin/bash
sudo apt-get update
sudo apt-get upgrade
sudo apt-get dist-upgrade

sudo apt-get install build-essential zlibc \
zlib1g-dev ruby ruby-dev openssl libxslt-dev \
libxml2-dev libssl-dev libreadline6 libreadline6-dev \
libyaml-dev libsqlite3-dev sqlite3 unzip

wget https://s3.amazonaws.com/bosh-cli-artifacts/bosh-cli-2.0.28-linux-amd64

sudo chown root:root bosh-cli-2.0.28-linux-amd64
sudo chmod 755 bosh-cli-2.0.28-linux-amd64

sudo mv bosh-cli-2.0.28-linux-amd64 /usr/local/bin/bosh

wget https://codeload.github.com/cloudfoundry/bosh-deployment/zip/3ad64e6d552f4ab6aa3816cd8a6f868587db0202

unzip 3ad64e6d552f4ab6aa3816cd8a6f868587db0202 -d bosh-deployment
rm 3ad64e6d552f4ab6aa3816cd8a6f868587db0202
mv -v ~/bosh-deployment/bosh-deployment-3ad64e6d552f4ab6aa3816cd8a6f868587db0202/* ~/bosh-deployment/
rm -rf ~/bosh-deployment/bosh-deployment-3ad64e6d552f4ab6aa3816cd8a6f868587db0202

cd ~/bosh-deployment

bosh create-env bosh.yml \
--state=bosh-state.json \
--vars-store=bosh-creds.yml \
-o vsphere/cpi.yml \
-o uaa.yml \
-o misc/powerdns.yml \
-o credhub.yml \
-v director_name=bosh \
-v internal_cidr=192.168.2.0/24 \
-v internal_gw=192.168.2.1 \
-v internal_ip=192.168.2.201 \
-v network_name='DPortGroup_LAN' \
-v vcenter_dc='HomeDC' \
-v vcenter_ds='vsanDatastore' \
-v vcenter_ip=192.168.2.66 \
-v vcenter_user='administrator@vsphere.local' \
-v vcenter_password='Lvclm@55!' \
-v vcenter_templates=kubo \
-v vcenter_vms=kubo \
-v vcenter_disks=vsanDatastore \
-v vcenter_cluster=MCCluster \
-v dns_recursor_ip=192.168.2.33

read -p "Move bosh director and stemcell to kubo Resource Pool. Press any key to continue..." -n1 -s

bosh alias-env kubo -e 192.168.2.201 --ca-cert <(bosh int ~/bosh-deployment/bosh-creds.yml --path /director_ssl/ca)
export BOSH_CLIENT=admin
export BOSH_CLIENT_SECRET=$(bosh int ~/bosh-deployment/bosh-creds.yml --path /admin_password)
bosh -e kubo env
cd ~

git clone -b v0.7.0 https://github.com/cloudfoundry-incubator/kubo-deployment
cd kubo-deployment

#read -p "Upload or create cloud-config-01.yml and kubo-deployment-01.yml. Press any key to continue..." -n1 -s
cp ~/CFCR/cloud-config-01.yml ~/kubo-deployment/cloud-config-01.yml
cp ~/CFCR/kubo-deployment-01.yml ~/kubo-deployment/kubo-deployment-01.yml

bosh -e kubo update-cloud-config cloud-config-01.yml
wget https://s3.amazonaws.com/bosh-core-stemcells/vsphere/bosh-stemcell-3421.11-vsphere-esxi-ubuntu-trusty-go_agent.tgz
bosh -e kubo upload-stemcell ./bosh-stemcell-3421.11-vsphere-esxi-ubuntu-trusty-go_agent.tgz

read -p "Move stemcell to kubo Resource Pool. Press any key to continue..." -n1 -s

wget https://github.com/cloudfoundry-incubator/kubo-release/releases/download/v0.7.0/kubo-release-0.7.0.tgz
bosh -e kubo upload-release kubo-release-0.7.0.tgz
bosh -e kubo -d kubo-cluster-01 deploy kubo-deployment-01.yml
bosh -e kubo deployments
bosh -e kubo instances
read -p "Kubernetes deployment complete, please review above. Press any key to continue..." -n1 -s

cd ~
wget https://github.com/cloudfoundry-incubator/credhub-cli/releases/download/1.4.0/credhub-linux-1.4.0.tgz
tar xvzf credhub-linux-1.4.0.tgz
sudo chown root:root credhub
sudo chmod 755 credhub
sudo mv credhub /usr/local/bin
curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl
sudo chown root:root kubectl
sudo chmod 755 kubectl
sudo mv kubectl /usr/local/bin

cd bosh-deployment
bosh -e kubo int "./bosh-creds.yml" --path="/uaa_ssl/ca" > credhubca.crt
bosh -e kubo int "./bosh-creds.yml" --path="/credhub_tls/ca" > credhub.crt
credhub login \
-u credhub-cli \
-p $(bosh -e kubo int "./bosh-creds.yml" --path "/credhub_cli_password") \
-s "https://192.168.2.201:8844" --ca-cert credhubca.crt --ca-cert credhub.crt

bosh int <(credhub get -n "/bosh/kubo-cluster-01/tls-kubernetes" --output-json) \
--path=/value/ca > kubecert.crt

kubectl config set-cluster "kubo-cluster-01" \
--server="https://192.168.2.203" \
--certificate-authority=kubecert.crt \
--embed-certs=true

kubectl config set-credentials "kubo-cluster-admin" \
--token="kubopassword"


kubectl config set-context "kubo-cluster-01" \
--cluster="kubo-cluster-01" \
--user="kubo-cluster-admin"

kubectl config use-context "kubo-cluster-01"
kubectl get pods --namespace=kube-system