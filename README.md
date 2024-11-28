# elastic_install
Script supports Elastic >8.x
node.master and node.data is removed after 8.x
instead you need to use node.roles:[master,data]


Edit Master and Data Node configurations in 
master.yaml and data.yaml
describe your seeds 


git clone ...
cd elastic/-install
chmod +x installelastic.sh

./installelastic.sh clustername master|data node_name

