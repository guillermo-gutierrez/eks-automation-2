# Changelog

0.0.5 (2023-06-24)
* AMX-PPL-CC-DES-EKS-PIPELINE-CF.yaml: Add Make EKS Private stage
* AMX-PPL-CC-EC2-DEPLOYER-IAM-EKSCTL-CF.yaml: Remove AssumeRole for KUBECTL-ROLE
* buildspec/cluster.yaml: Add X-Ray Trace publish policy
* buildspec/configure-eks.yaml: Fix typo in ADOT Collector creation
* buildspec/make-eks-private.yaml: Add Make Private code

0.0.4
* buildspec/configure-eks.yaml: Bring all of the code to yaml file.
* buildspec/deploy-eks.yaml: Make unzip quiet.

0.0.3 (2023-06-18)
* AMX-PPL-CC-DES-EKS-PIPELINE-CF.yaml: Adjust Import Role Name values
* AMX-PPL-CC-DES-IAM-PERMISSIONS-EKS-CF.yaml: Adjut Export Role Name values
* bin/ConfigureEks.sh: Role Name Adjustment

0.0.2 (2023-06-09)
* AMX-PPL-CC-DES-EKS-PIPELINE-CF.yaml
* AMX-PPL-CC-DES-IAM-PERMISSIONS-EKS-CF.yaml
* ConfigureEks.sh: Moved to bin directory bin/ConfigureEks.sh
* buildspec-configure-eks.yaml: Moved to buildspec directory buildspec/configure-eks.yaml

0.0.1 (2023-06-08) - Initial release
* AMX-PPL-CC-DES-EKS-PIPELINE-CF.yaml
* AMX-PPL-CC-DES-IAM-PERMISSIONS-EKS-CF.yaml
* ConfigureEks.sh
* Procedimiento-Despliegue-Pipeline.txt
* bin/automation_eks_cluster.sh
* bin/tmp/cluster.yaml
* buildspec-configure-eks.yaml
* manifests/aws-logging-cloudwatch-configmap.yaml
* manifests/aws-observability-namespace.yaml
* manifests/hpa-cpu.yaml
