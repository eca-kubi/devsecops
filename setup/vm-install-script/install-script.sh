#!/bin/bash

echo ".........----------------#################._.-.-INSTALL-.-._.#################----------------........."
PS1='\[\e[01;36m\]\u\[\e[01;37m\]@\[\e[01;33m\]\H\[\e[01;37m\]:\[\e[01;32m\]\w\[\e[01;37m\]\$\[\033[0;37m\] '
echo "PS1='\[\e[01;36m\]\u\[\e[01;37m\]@\[\e[01;33m\]\H\[\e[01;37m\]:\[\e[01;32m\]\w\[\e[01;37m\]\$\[\033[0;37m\] '" >> ~/.bashrc
sed -i '1s/^/force_color_prompt=yes\n/' ~/.bashrc
source ~/.bashrc

# Don't ask to restart services after apt update, just do it.
[ -f /etc/needrestart/needrestart.conf ] && sed -i 's/#\$nrconf{restart} = \x27i\x27/$nrconf{restart} = \x27a\x27/' /etc/needrestart/needrestart.conf

apt-get autoremove -y  #removes the packages that are no longer needed
apt-get update
systemctl daemon-reload

KUBE_LATEST=$(curl -L -s https://dl.k8s.io/release/stable.txt | awk 'BEGIN { FS="." } { printf "%s.%s", $1, $2 }')
mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/${KUBE_LATEST}/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${KUBE_LATEST}/deb/ /" >> /etc/apt/sources.list.d/kubernetes.list

apt-get update
KUBE_VERSION=$(apt-cache madison kubeadm | head -1 | awk '{print $3}')
apt-get install -y docker.io vim build-essential jq python3-pip kubelet kubectl kubernetes-cni kubeadm containerd
pip3 install jc

### UUID of VM
### comment below line if this Script is not executed on Cloud based VMs
jc dmidecode | jq .[1].values.uuid -r

systemctl enable kubelet

echo ".........----------------#################._.-.-KUBERNETES-.-._.#################----------------........."
rm -f /root/.kube/config
kubeadm reset -f

mkdir -p /etc/containerd
containerd config default | sed 's/SystemdCgroup = false/SystemdCgroup = true/' > /etc/containerd/config.toml
systemctl restart containerd

# uncomment below line if your host doesnt have minimum requirement of 2 CPU
# kubeadm init --pod-network-cidr '10.244.0.0/16' --service-cidr '10.96.0.0/16' --ignore-preflight-errors=NumCPU --skip-token-print
kubeadm init --pod-network-cidr '10.244.0.0/16' --service-cidr '10.96.0.0/16'  --skip-token-print

mkdir -p ~/.kube
cp -i /etc/kubernetes/admin.conf ~/.kube/config

kubectl apply -f "https://github.com/weaveworks/weave/releases/download/v2.8.1/weave-daemonset-k8s-1.11.yaml"
kubectl rollout status daemonset weave-net -n kube-system --timeout=90s
sleep 5

echo "untaint controlplane node"
node=$(kubectl get nodes -o=jsonpath='{.items[0].metadata.name}')
for taint in $(kubectl get node $node -o jsonpath='{range .spec.taints[*]}{.key}{":"}{.effect}{"-"}{end}')
do
    kubectl taint node $node $taint
done
kubectl get nodes -o wide

echo ".........----------------#################._.-.-Docker-.-._.#################----------------........."

cat > /etc/docker/daemon.json <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "storage-driver": "overlay2"
}
EOF
mkdir -p /etc/systemd/system/docker.service.d

systemctl daemon-reload
systemctl restart docker
systemctl enable docker


echo ".........----------------#################._.-.-Java and MAVEN-.-._.#################----------------........."
apt install openjdk-11-jdk maven -y
java -version
mvn -v

echo ".........----------------#################._.-.-JENKINS-.-._.#################----------------........."
# Jenkins LTS requires Java 21 or later. Java 11 (installed above) is kept for the
# application's Maven build (pom.xml targets Java 1.8), so install a dedicated
# Java 21 runtime for the Jenkins controller and pin the service to it below.
apt-get install -y fontconfig openjdk-21-jre

# Jenkins rotated its repository signing key: the old jenkins.io-2023.key expired on
# 2026-03-26 and no longer signs the debian-stable repo. Use the current (2026) key,
# otherwise apt fails with "NO_PUBKEY ... The repository is not signed" and jenkins
# has no installation candidate. See https://www.jenkins.io/doc/book/installing/linux/
install -d -m 0755 /usr/share/keyrings /etc/apt/sources.list.d
# Remove any stale/expired Jenkins key and repo definition from earlier runs
rm -f /usr/share/keyrings/jenkins.gpg /usr/share/keyrings/jenkins-keyring.asc \
      /etc/apt/sources.list.d/jenkins.list
# -f makes curl fail (non-zero) instead of writing an empty/invalid keyring on HTTP errors
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key \
     -o /usr/share/keyrings/jenkins-keyring.asc
chmod 644 /usr/share/keyrings/jenkins-keyring.asc
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" > /etc/apt/sources.list.d/jenkins.list
apt-get update
apt-get install -y jenkins

# Pin the Jenkins controller to Java 21. The packaged unit ships JAVA_HOME and
# JENKINS_JAVA_CMD commented out, so without this Jenkins falls back to the default
# `java` on PATH (Java 11) and refuses to start. Resolve the JDK path so this works
# on amd64/arm64, then override via a systemd drop-in.
JENKINS_JAVA_HOME=$(ls -d /usr/lib/jvm/java-21-openjdk-* 2>/dev/null | head -1)
[ -n "${JENKINS_JAVA_HOME}" ] || { echo "ERROR: Java 21 not found under /usr/lib/jvm" >&2; exit 1; }
mkdir -p /etc/systemd/system/jenkins.service.d
cat > /etc/systemd/system/jenkins.service.d/java.conf <<EOF
[Service]
Environment="JAVA_HOME=${JENKINS_JAVA_HOME}"
Environment="JENKINS_JAVA_CMD=${JENKINS_JAVA_HOME}/bin/java"
EOF
systemctl daemon-reload
systemctl enable jenkins
systemctl start jenkins
usermod -a -G docker jenkins
echo "jenkins ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

echo ".........----------------#################._.-.-COMPLETED-.-._.#################----------------........."
