# Wiz Technical Exercise — Build & Demo Runbook

## 1. Prerequisites
- AWS CLI configured, an EC2 key pair created in your target region
- Terraform >= 1.5, kubectl, helm, eksctl, docker
- An `.tfvars` file (gitignored) with:
  ```hcl
  your_name             = "Your Name"
  key_pair_name          = "your-ec2-keypair"
  mongo_admin_password   = "set-a-strong-password"
  aws_region             = "us-east-1"
  ```

## 2. Build order

```bash
cd terraform
terraform init
terraform plan -var-file=secrets.auto.tfvars
terraform apply -var-file=secrets.auto.tfvars
```

This creates: VPC (public + private subnets), NAT gateway, the Mongo EC2
instance (old AMI, public SSH, overprivileged IAM role, outdated MongoDB via
user-data), the public S3 backup bucket, the EKS cluster (private subnets),
and an ECR repo.

Capture outputs:
```bash
terraform output
```

## 3. Point kubectl at the new cluster
```bash
aws eks update-kubeconfig --name <eks_cluster_name> --region <region>
kubectl get nodes
```

## 4. Install the ALB ingress controller
```bash
../scripts/install_alb_controller.sh <eks_cluster_name> <region>
```

## 5. Build, validate, and push the app image
```bash
../scripts/build_and_push.sh "Your Name" <ecr_repo_url> <region>
```
The script prints the contents of `/wizexercise.txt` from inside the built
image before pushing — keep that terminal output/screenshot for your
presentation as proof of how the file got in and that it exists.

## 6. Create the Mongo connection Secret
Get the Mongo VM's **private IP** from `terraform output mongo_vm_private_ip`,
then:
```bash
kubectl create namespace wiz-exercise
kubectl create secret generic mongo-connection \
  --namespace wiz-exercise \
  --from-literal=MONGO_URI="mongodb://appuser:<password>@<mongo_private_ip>:27017/todoapp?authSource=todoapp"
```

## 7. Deploy the app to Kubernetes
Edit `k8s/03-deployment.yaml` to set the real ECR image URL, then:
```bash
kubectl apply -f ../k8s/00-namespace.yaml
kubectl apply -f ../k8s/02-rbac.yaml
kubectl apply -f ../k8s/03-deployment.yaml
kubectl apply -f ../k8s/04-service.yaml
kubectl apply -f ../k8s/05-ingress.yaml
```

Wait for the ALB to provision:
```bash
kubectl get ingress -n wiz-exercise -w
```

## 8. Validate everything end-to-end
```bash
# Pods healthy, running in private subnets
kubectl get pods -n wiz-exercise -o wide

# Prove wizexercise.txt is really in the running container
kubectl exec -n wiz-exercise deploy/todo-app -- cat /wizexercise.txt

# Prove cluster-admin binding (talking point for the demo)
kubectl auth can-i '*' '*' --as=system:serviceaccount:wiz-exercise:todo-app-sa

# Hit the app via the ALB DNS name from the ingress
curl http://<alb-dns-name>/api/todos

# Confirm the backup bucket is public
curl https://<backup_bucket_name>.s3.amazonaws.com/
```

## 9. Demo script for the panel (~45 min)
1. Slide: architecture diagram + intentional weaknesses summary (below).
2. `kubectl get nodes,pods -n wiz-exercise` — show cluster is up, pods private.
3. `kubectl exec ... cat /wizexercise.txt` — prove the required file.
4. Browser: open the app via ALB DNS, add a todo, refresh to prove persistence.
5. SSH into the Mongo VM (`ssh -i key.pem ubuntu@<public_ip>`), `mongo` shell,
   show the `todos` collection has the record you just added — proves the
   app -> Mongo data path end to end.
6. `curl` the public S3 bucket to show the backup file downloadable anonymously.
7. Walk through each intentional weakness (below) and the realistic attack
   path/blast radius, and how a CSPM tool would detect + prioritize it.
8. Trigger a pipeline live (e.g. a small no-op commit to `app/`) and show
   the Trivy/Checkov scan step and the manual-approval gate on `production`.
9. Demo the cloud-native controls: CloudTrail trail status, the Config
   preventative rule catching a throwaway open-SSH security group, and a
   GuardDuty finding (real or sample-generated).
10. Discuss build challenges and what you'd harden in a real environment.

## 10. Intentional weaknesses — talking points

| # | Weakness | Where | Real-world risk |
|---|----------|-------|------------------|
| 1 | SSH open to `0.0.0.0/0` | Mongo VM security group | Internet-wide brute-force / exploit surface on an EC2 host |
| 2 | 1+ year outdated Linux AMI | Mongo VM | Missing OS-level CVE patches |
| 3 | Overly permissive IAM role (`AmazonEC2FullAccess`) on the VM | Mongo VM instance profile | A compromised VM could create/modify other compute resources — lateral movement / resource hijacking |
| 4 | 1+ year outdated MongoDB (4.4.x) | Mongo VM | Missing DB-layer CVE patches |
| 5 | Public-read + public-list S3 bucket | Backup bucket | Full DB backups (including all app data) downloadable by anyone on the internet |
| 6 | `cluster-admin` bound to the app's ServiceAccount | K8s RBAC | Any RCE/SSRF in the app becomes a full cluster takeover |
| 7 | DB reachable only from private subnet, but VM otherwise exposed | Mongo SG | Shows partial hardening — good contrast point: auth + network scoping done right on the DB port, wrong everywhere else |

Attack chain narrative: public SSH/outdated OS on the Mongo VM → compromise
the instance → pivot using its overprivileged IAM role to create/attach
resources in the account, or read the public S3 bucket directly for an
even easier path to the full dataset without touching the VM at all.
Separately, any compromise of the web app pod (e.g. an app-layer RCE)
inherits `cluster-admin`, giving full control of the Kubernetes cluster.

## 11. DevSecOps: VCS + CI/CD pipelines

### 11.1 Repo setup
```bash
git init
git remote add origin git@github.com:<your-org>/<your-repo>.git
git add .
git commit -m "Initial Wiz exercise environment"
git push -u origin main
```
- Enable branch protection on `main`: require PR review before merge, require
  status checks to pass, block force-pushes.
- Enable GitHub secret scanning + push protection (Settings → Code security).
- `.github/CODEOWNERS` requires review on `terraform/`, `k8s/`, and
  `.github/workflows/` changes — update the username in that file first.

### 11.2 One-time AWS setup for GitHub OIDC
Before the pipelines can run, apply the OIDC role once (bootstrap via local
Terraform, since the pipeline needs the role to exist to authenticate):
```bash
cd terraform
terraform apply -target=aws_iam_openid_connect_provider.github -target=aws_iam_role.github_actions \
  -var="github_org_repo=<your-org>/<your-repo>" -var-file=secrets.auto.tfvars
terraform output github_actions_role_arn
```
Add these as GitHub repo secrets/variables (Settings → Secrets and variables → Actions):
- Secret `AWS_DEPLOY_ROLE_ARN` = the output above
- Secret `MONGO_ADMIN_PASSWORD`
- Secret `EC2_KEY_PAIR_NAME`
- Variable `YOUR_NAME`

Create a GitHub **Environment** named `production` and require a reviewer on
it — this is what gates the `apply`/`deploy` jobs behind manual approval.

### 11.3 The three workflows
| Workflow | Trigger | What it does |
|---|---|---|
| `iac-deploy.yml` | PR/push touching `terraform/` | fmt/validate → Checkov + tfsec scan → plan on PR → manual-approved apply on merge |
| `app-build-deploy.yml` | PR/push touching `app/` | build image → validate `wizexercise.txt` → Trivy scan → push to ECR → manual-approved `kubectl set image` rollout |
| `repo-security-scan.yml` | every PR/push | gitleaks secret scanning across the repo |

Both scanners currently run in `soft_fail`/non-blocking mode so your
intentionally-vulnerable resources don't block the pipeline — flip
`soft_fail: false` / `exit-code: "1"` once you've triaged findings, and
mention in your presentation that you did this deliberately.

### 11.4 Optional: simulate an attack
With CloudTrail + GuardDuty in place (section 12), you can demo:
```bash
# From your own machine, simulate the attack path against the exposed VM
ssh -i key.pem ubuntu@<mongo_vm_public_ip>
# then, using the VM's overprivileged instance role:
aws ec2 describe-instances --region <region>
```
Show the corresponding CloudTrail event and/or a GuardDuty finding for the
API call made from the instance's credentials.

## 12. Cloud-native security controls

Applying `security_controls.tf` and `cloudtrail.tf` gives you:
- **Audit logging (required):** a multi-region CloudTrail trail with log
  file validation, writing to a private (non-public) S3 bucket.
- **Preventative control (required):** an AWS Config rule
  (`INCOMING_SSH_DISABLED`) with **automatic remediation** via the
  `AWS-DisablePublicAccessForSecurityGroup` SSM document — it revokes any
  new security group's open SSH ingress automatically. The exercise's
  required-open Mongo SG is tagged `wiz-exercise-intentional-exception=true`
  so this control doesn't remediate away your required weakness; you can
  demo the control working against a throwaway test SG instead.
- **Detective control (recommended):** GuardDuty, enabled account-wide.

### Demo commands
```bash
# Show audit logging is active
aws cloudtrail get-trail-status --name wiz-exercise-trail

# Show the Config rule and its compliance state
aws configservice describe-config-rules --config-rule-names wiz-exercise-restricted-ssh
aws configservice get-compliance-details-by-config-rule --config-rule-name wiz-exercise-restricted-ssh

# Demonstrate the preventative control: create a throwaway SG with open SSH
aws ec2 create-security-group --group-name demo-open-ssh --description "demo" --vpc-id <vpc_id>
aws ec2 authorize-security-group-ingress --group-id <sg_id> --protocol tcp --port 22 --cidr 0.0.0.0/0
# ...wait a few minutes for Config to evaluate and auto-remediate, then show:
aws ec2 describe-security-group-rules --filters Name=group-id,Values=<sg_id>

# GuardDuty findings (generate sample findings if nothing real has fired yet)
aws guardduty list-detectors
aws guardduty create-sample-findings --detector-id <detector_id> --finding-types Backdoor:EC2/C&CActivity.B!DNS
aws guardduty list-findings --detector-id <detector_id>
```

## 13. Teardown (after each session, to control cost)
```bash
kubectl delete -f ../k8s/05-ingress.yaml   # let the ALB deprovision first
cd ../terraform
terraform destroy -var-file=secrets.auto.tfvars
```
