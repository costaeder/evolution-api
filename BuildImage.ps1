# -----------------------------------------------
# BuildImage.ps1  –  usando Podman + AWS ECR
# -----------------------------------------------

$ErrorActionPreference = "Stop"

# --- Parâmetros reutilizáveis -------------------
$Region = "us-east-2"
$AccountId = "130811782740"
$RepoName  = "evolution"
$Tag       = "custom-2.3.0"

$Registry = "$AccountId.dkr.ecr.$Region.amazonaws.com"
$Repo     = "$Registry/$RepoName"
$Image    = "${Repo}:$Tag"

# --- Autenticação no ECR ------------------------
# 1) Via AWS Tools for PowerShell (mantém seu padrão atual):
(Get-ECRLoginCommand -Region $Region).Password |
    podman login --username AWS --password-stdin $Registry

#    — OU —
# 2) Via AWS CLI, se preferir:
# aws ecr get-login-password --region $Region |
#     podman login --username AWS --password-stdin $Registry

# --- Build, tag & push --------------------------
podman build -t "evolution:$Tag" -f .\Dockerfile .
podman tag  "evolution:$Tag" $Image
podman push $Image
