#!/bin/bash
set -euo pipefail

VER="v1.0.0"

function err_report() {
  echo "errexit on line $(caller)" >&2
}

trap err_report ERR

# Based on https://cloudhero.io/creating-users-for-your-kubernetes-cluster
[ "$(basename "$0")" = "k8scc.sh" ] || echo "Wrong filename for this script - please use original version in https://github.com/rhmarras/k8scc or fork it :)"

function usage()
{
    echo -e "Please provide the required arguments "
    echo -e ""
    echo -e $0
    echo -e "\t-h --help"
    echo -e "\t--apiurl==<k8s_api_url>"
    echo -e "\t--clustername==<k8s_cluster_name>"
    echo -e "\t--user==<user_name>"
    echo -e "\t--group==<user_group>"
    echo -e "\t--days==<days until your new cert is invalidated>"
    echo -e ""
    echo -e "or check out other non-mandatory options:"
    echo -e ""
    echo -e "\t--example   <--- print a usage example"
    echo -e "\t--license   <--- print this programs's license"
    echo -e "\t--version   <--- print this programs's version"
    echo -e "Make sure you have the ca.crt and ca.key files from your K8s cluster in the CA directory."

}

function example()
{ 
echo -e "Remember you need to get the root certificate and key from your Kubernetes clusters. For kubeadm/kubespray, you can copy it from any master node, as it’s located in the /etc/kubernetes/ssl directory. For Kops, it’s in the S3 bucket configured at install time. The S3 paths are: \n \n ca.crt: s3://state-store/<cluster-name>/pki/issued/ca/<id>.crt \n ca.key: s3://state-store/<cluster-name>/pki/private/ca/<id>.key \n \n Put them in the CA folder and name them ca.crt and ca.key."
echo "\
echo 
This is an example of a Role configuration yaml file for k8s....\
\
kind: Role\
apiVersion: rbac.authorization.k8s.io/v1\
metadata:\
  namespace: smithns\
  name: smithns-rw-role\
rules:\
- apiGroups: ["", "batch", "extensions", "apps"]\
  resources: ["*"]\
  verbs: ["*"]\
\
\
This is an example of a Role binding configuration yaml file for k8s...\
\
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: smithrolebinding
  namespace: smithns
subjects:
- kind: User
  name: smith
  apiGroup: ""
roleRef:
  kind: Role
  name: smithns-rw-role
  apiGroup: rbac.authorization.k8s.io
\
\
you would apply them with:\
kubectl apply -f filename.yaml\ 
\ 
\
If you want to delete the authorization, just delete de role/rolebinding from the cluster and your user will lose access\
\
Cheers!"
}

function license() {
  echo "    <k8scc.sh - automates the process of creating user certs for k8s RBAC configuration.>\
    Copyright (C) 2020  Rodrigo H. Marras - marras.com.ar\
\
    This program is free software: you can redistribute it and/or modify\
    it under the terms of the GNU General Public License as published by\
    the Free Software Foundation, either version 3 of the License, or\
    (at your option) any later version.\
\
    This program is distributed in the hope that it will be useful,\
    but WITHOUT ANY WARRANTY; without even the implied warranty of\
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the\
    GNU General Public License for more details.\
\
    You should have received a copy of the GNU General Public License\
    along with this program.  If not, see <https://www.gnu.org/licenses/>."
}
while [ "$1" != "" ]; do
    PARAM=`echo $1 | awk -F"==" '{print $1}'`
    VALUE=`echo $1 | awk -F"==" '{print $2}'`
    case $PARAM in
        -h | --help)
            usage
            exit
            ;;
        --apiurl)
            K8S_API_URL="$VALUE"
            ;;
        --clustername)
            CLUSTER_NAME="$VALUE"
            ;;
        --user)
            USER_NAME="$VALUE"
            ;;
        --group)
            GROUP_NAME="$VALUE"
            ;;
        --days)
            DAYS="$VALUE"
            ;;
        --version)
            echo -e "k8scc.sh version ${VER} - GPLv3 - Author: Rodrigo H. Marras\nProgrammed with love \xf0\x9f\x94\x86""; exit 0
            ;;
        --example)
            example; exit 0
            ;;
        --license)
            license; exit 0
            ;;
        *)
            echo -e "ERROR: unknown parameter \"$PARAM\""
            usage
            exit 1
            ;;
    esac
    shift
done


# Validation section
[ -z ${K8S_API_URL} ] && { echo "Error, must provide --apiurl <k8s api url>"; echo ""; usage; exit 1; }
[ -z ${CLUSTER_NAME} ] && { echo "Error, must provide --clustername <clustername>"; echo ""; usage; exit 1; }
[ -z ${USER_NAME} ] && { echo "Error, must provide --user <user name>"; echo ""; usage; exit 1; }
[ -z ${GROUP_NAME} ] && { echo "Error, must provide --group <group name>"; echo ""; usage; exit 1; }
[ -z ${DAYS} ] && { echo "Error, must provide --days <how many days until this cert expires>"; echo ""; usage; exit 1; }
[ -f "CA/ca.crt" ] && echo "ca.crt exist. Good!" || { echo "Error! CA/ca.crt file is missing."; echo ""; usage; exit 1; }
[ -f "CA/ca.key" ] && echo "ca.key exist. Good!" || { echo "Error! CA/ca.key file is missing."; echo ""; usage; exit 1; }
[ -d "CA/" ] && echo "Directory OUT exists. Good!" || { echo "Creating OUT directory"; mkdir OUT; }
`which openssl>/dev/null` && echo "openssl installed. Good!" || { echo "openssl not in path or not installed - aborting"; exit 1; }


# Let's sanitize the filenames for the certificates using the username as base
FILE_NAME=$(sed 's/[^0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_-]/_/g' <<< "$USER_NAME")
echo "Using ${FILE_NAME} for the output files"

echo "First, we need to generate a private key for our new user:"
openssl genrsa -out ${FILE_NAME}.key 2048

echo "Next, we create a CSR using the key we just generated"
openssl req -new -key ${FILE_NAME}.key -out ${FILE_NAME}.csr -subj "/CN=${USER_NAME}/O=${GROUP_NAME}"

echo "Now we create a certificate using our private key, our CSR, and our CA for signing."

openssl x509 -req -in ${FILE_NAME}.csr -CA CA/ca.crt -CAkey CA/ca.key -CAcreateserial -out OUT/${FILE_NAME}.crt -days ${DAYS}


CA_CRT_BASE64=$(base64 CA/ca.crt)
CLIENT_CRT_BASE64=$(base64 OUT/${USER_NAME}.crt)
CLIENT_KEY_BASE64=$(base64 OUT/${USER_NAME}.key)

echo "apiVersion: v1\
current-context: ${USER_NAME}-ctx\
preferences: {}\
clusters:\
- cluster:\
    certificate-authority-data: ${CA_CRT_BASE64}\
    server: ${K8S_API_URL}\
  name: ${CLUSTER_NAME}\
contexts:\
- context:\
    cluster: ${CLUSTER_NAME}\
    user: ${USER_NAME}\
  name: ${USER_NAME}-ctx\
kind: Config\
users:\
- name: ${USER_NAME}\
  user:\
    client-certificate-data: ${CLIENT_CRT_BASE64}\
    client-key-data: ${CLIENT_KEY_BASE64}" > OUT/config.${USER_NAME}

echo "OUT/config.${USER_NAME} file created - please deliver it to your user IN A SECURE WAY - make sure you configured your role and role-binding properly in your k8s cluster"
echo "Thank you for using k8scc.sh"
