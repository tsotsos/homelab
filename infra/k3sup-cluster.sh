k3sup install --ip 10.0.2.21 --user root --cluster --k3s-version v1.26.15+k3s1 --k3s-channel stable --no-extras
k3sup join --ip 10.0.2.22 --user root --server-user root  --server-ip 10.0.2.21 --server --k3s-version v1.26.15+k3s1 --k3s-channel stable --no-extras
k3sup join --ip 10.0.2.23 --user root --server-user root  --server-ip 10.0.2.21 --server --k3s-version v1.26.15+k3s1 --k3s-channel stable --no-extras

k3sup join --ip 10.0.2.24 --user root --server-user root  --server-ip 10.0.2.21 --k3s-version v1.26.15+k3s1 --k3s-channel stable && 
k3sup join --ip 10.0.2.25 --user root --server-user root  --server-ip 10.0.2.21 --k3s-version v1.26.15+k3s1 --k3s-channel stable &&
k3sup join --ip 10.0.2.26 --user root --server-user root  --server-ip 10.0.2.21 --k3s-version v1.26.15+k3s1 --k3s-channel stable &&
k3sup join --ip 10.0.2.27 --user root --server-user root  --server-ip 10.0.2.21 --k3s-version v1.26.15+k3s1 --k3s-channel stable &&
k3sup join --ip 10.0.2.28 --user root --server-user root  --server-ip 10.0.2.21 --k3s-version v1.26.15+k3s1 --k3s-channel stable &&
k3sup join --ip 10.0.2.29 --user root --server-user root  --server-ip 10.0.2.21 --k3s-version v1.26.15+k3s1 --k3s-channel stable 
