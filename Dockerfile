FROM ubuntu:24.04

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    coreutils \
    sed \
    && rm -rf /var/lib/apt/lists/*

# Create a test user (avoid running as root)
RUN useradd -m -s /bin/bash tester
USER tester
WORKDIR /home/tester

# Copy the script and tests
COPY --chown=tester:tester bash-autosuggestions.sh /home/tester/.local/share/bash-autosuggestions/bash-autosuggestions.sh
COPY --chown=tester:tester test-automated.sh /home/tester/test-automated.sh

# Seed bash history with realistic commands so suggestions appear immediately
RUN mkdir -p /home/tester/.local/share/bash-autosuggestions && \
    cat > /home/tester/.bash_history << 'EOF'
kubectl get pods -n production -o wide
kubectl get services -n production
kubectl describe pod my-app-7b4f5c8d9-x2k3m -n production
kubectl logs -f deployment/my-app -n production
docker compose up -d
docker compose logs -f
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
terraform plan -var-file=prod.tfvars
terraform apply -var-file=prod.tfvars -auto-approve
ansible-playbook -i inventory/prod site.yml
git status
git add -A && git commit -m "fix: resolve deployment issue"
git push origin main
helm upgrade --install my-app ./charts/my-app -n production -f values-prod.yaml
curl -s https://api.example.com/health | jq .
ssh devops@bastion.example.com
grep -rn "ERROR" /var/log/app/*.log | tail -20
find /etc/kubernetes -name "*.yaml" -mtime -1
systemctl status kubelet
journalctl -u kubelet -f --no-pager
EOF

# Configure bashrc to source the script + nice prompt
RUN cat >> /home/tester/.bashrc << 'BASHRC'

# History settings (important for autosuggestions)
export HISTSIZE=10000
export HISTFILESIZE=10000
export HISTCONTROL=ignoredups:erasedups
shopt -s histappend

# Optional: customize suggestion color (default is fine)
# BASH_AUTOSUGGEST_HIGHLIGHT_STYLE="38;5;240"

# Load bash-autosuggestions
source ~/.local/share/bash-autosuggestions/bash-autosuggestions.sh
BASHRC

CMD ["/bin/bash", "-l"]
