# elastic_install
Script supports Elastic >8.x
node.master and node.data is removed after 8.x
instead you need to use node.roles:[master,data]


!! The script is writen for ubuntu 22.04 
you may need to install some commands like python , git etc depending on your operating system 

1- 

git clone ...
cd elastic-install


2-

Edit Master Elastic configurations in  
  Edit elactic_config.env


    describe your seeds  // !!! consider first IP as master node. 


3-
chmod +x installelastic.sh

    ./installelastic.sh clustername master|data node_name

for master cluster  (./installelastic.sh my-cluster master master-1)

Run same command for all instances. 

* At Master once installation completes, It generates CA certificate and  then creates a server to transfer certificates to clients (data nodes)

Once certification transfers completed , Client installation ends  It waits you to press  x to continue process on server side. 


Done

curl -X GET "localhost:9200/_cluster/health"

# Kibana  Installation
   Edit kibana_config.env


!! For testing purposes kibana listens on port 0.0.0.0 

