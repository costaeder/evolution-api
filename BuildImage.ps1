(Get-ECRLoginCommand).Password | podman login --username AWS --password-stdin 130811782740.dkr.ecr.us-east-2.amazonaws.com
#

$ErrorActionPreference = "Stop"
 
 
 

podman build -t evolution -f .\Dockerfile .
podman tag evolution:latest 130811782740.dkr.ecr.us-east-2.amazonaws.com/evolution
podman push 130811782740.dkr.ecr.us-east-2.amazonaws.com/evolution