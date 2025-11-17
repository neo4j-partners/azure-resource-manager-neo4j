# Development Environment Setup

This guide provides step-by-step instructions for setting up your development environment to work with Bicep templates in the Azure Neo4j deployment infrastructure.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Required Tools](#required-tools)
- [Installation Instructions](#installation-instructions)
  - [macOS](#macos)
  - [Linux](#linux)
  - [Windows](#windows)
- [Post-Installation Setup](#post-installation-setup)
- [Verification](#verification)
- [IDE Setup](#ide-setup)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

Before setting up your development environment, ensure you have:

- **Operating System**: macOS, Linux (Ubuntu/Debian/RHEL), or Windows 10/11
- **Internet Connection**: Required for downloading tools and packages
- **Administrator/sudo Access**: Required for tool installation
- **Azure Subscription**: Required for deploying and testing templates

---

## Required Tools

The following tools are required for Bicep development:

| Tool | Minimum Version | Purpose |
|------|-----------------|---------|
| **Azure CLI** | 2.50.0+ | Deploy Bicep templates and manage Azure resources |
| **Bicep CLI** | 0.20.0+ | Compile and lint Bicep files |
| **Git** | 2.30.0+ | Version control and pre-commit hooks |
| **Code Editor** | Latest | VS Code recommended for Bicep development |

### Optional but Recommended

- **VS Code Bicep Extension** - Syntax highlighting, IntelliSense, and validation
- **Azure CLI Tools Extension** (VS Code) - Azure resource management from editor

---

## Installation Instructions

### macOS

#### 1. Install Homebrew (if not already installed)

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

#### 2. Install Azure CLI

```bash
brew update && brew install azure-cli
```

Verify installation:

```bash
az version
```

#### 3. Install Bicep CLI

Bicep CLI is now bundled with Azure CLI. To ensure you have the latest version:

```bash
az bicep install
az bicep upgrade
```

Verify Bicep installation:

```bash
az bicep version
```

Expected output: `Bicep CLI version 0.x.x (xxxxxxxx)`

#### 4. Install or Update Git

```bash
brew install git
```

Verify Git installation:

```bash
git --version
```

#### 5. Install Visual Studio Code (Optional)

```bash
brew install --cask visual-studio-code
```

---

### Linux

#### Ubuntu / Debian

##### 1. Install Azure CLI

```bash
# Get packages needed for the installation process
sudo apt-get update
sudo apt-get install ca-certificates curl apt-transport-https lsb-release gnupg

# Download and install the Microsoft signing key
sudo mkdir -p /etc/apt/keyrings
curl -sLS https://packages.microsoft.com/keys/microsoft.asc |
  gpg --dearmor |
  sudo tee /etc/apt/keyrings/microsoft.gpg > /dev/null
sudo chmod go+r /etc/apt/keyrings/microsoft.gpg

# Add the Azure CLI software repository
AZ_DIST=$(lsb_release -cs)
echo "deb [arch=`dpkg --print-architecture` signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ $AZ_DIST main" |
  sudo tee /etc/apt/sources.list.d/azure-cli.list

# Update repository information and install the azure-cli package
sudo apt-get update
sudo apt-get install azure-cli
```

Verify installation:

```bash
az version
```

##### 2. Install Bicep CLI

```bash
az bicep install
az bicep upgrade
```

Verify:

```bash
az bicep version
```

##### 3. Install Git

```bash
sudo apt-get install git
```

Verify:

```bash
git --version
```

##### 4. Install VS Code (Optional)

```bash
# Download and install from Microsoft
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
sudo install -D -o root -g root -m 644 packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg
sudo sh -c 'echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list'
rm -f packages.microsoft.gpg

sudo apt install apt-transport-https
sudo apt update
sudo apt install code
```

#### RHEL / CentOS / Fedora

##### 1. Install Azure CLI

**RHEL 9 / CentOS 9:**

```bash
# Import the Microsoft repository key
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc

# Add the Azure CLI repository
echo -e "[azure-cli]
name=Azure CLI
baseurl=https://packages.microsoft.com/yumrepos/azure-cli
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc" | sudo tee /etc/yum.repos.d/azure-cli.repo

# Install Azure CLI
sudo dnf install azure-cli
```

**RHEL 8 / CentOS 8:**

```bash
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
sudo dnf install -y https://packages.microsoft.com/config/rhel/8/packages-microsoft-prod.rpm
sudo dnf install azure-cli
```

Verify:

```bash
az version
```

##### 2. Install Bicep CLI

```bash
az bicep install
az bicep upgrade
az bicep version
```

##### 3. Install Git

```bash
sudo dnf install git
```

---

### Windows

#### 1. Install Azure CLI

Download and run the Azure CLI installer:
- [Azure CLI MSI Installer](https://aka.ms/installazurecliwindows)

Or using PowerShell:

```powershell
Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile .\AzureCLI.msi
Start-Process msiexec.exe -Wait -ArgumentList '/I AzureCLI.msi /quiet'
Remove-Item .\AzureCLI.msi
```

Verify (restart PowerShell after installation):

```powershell
az version
```

#### 2. Install Bicep CLI

```powershell
az bicep install
az bicep upgrade
az bicep version
```

#### 3. Install Git

Download and install Git for Windows:
- [Git for Windows](https://git-scm.com/download/win)

Or using Windows Package Manager:

```powershell
winget install --id Git.Git -e --source winget
```

Verify:

```powershell
git --version
```

#### 4. Install VS Code (Optional)

Download and install from:
- [Visual Studio Code](https://code.visualstudio.com/download)

Or using Windows Package Manager:

```powershell
winget install -e --id Microsoft.VisualStudioCode
```

---

## Post-Installation Setup

### 1. Configure Azure CLI

Login to your Azure account:

```bash
az login
```

This will open a browser window for authentication.

Set your default subscription (if you have multiple):

```bash
# List subscriptions
az account list --output table

# Set default subscription
az account set --subscription "Your Subscription Name or ID"

# Verify current subscription
az account show
```

### 2. Install Git Hooks

Clone the repository and install pre-commit hooks:

```bash
# Navigate to repository directory
cd /path/to/azure-neo4j-modernize

# Install pre-commit hooks
./scripts/install-git-hooks.sh
```

This will install the Bicep linter pre-commit hook that validates files before committing.

### 3. Configure Git

Set your Git identity (if not already configured):

```bash
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"
```

---

## Verification

Run the environment validation script to verify all tools are installed correctly:

```bash
./scripts/validate-environment.sh
```

This script checks:
- Azure CLI installation and version
- Bicep CLI installation and version
- Git installation and version
- Azure CLI login status
- Bicep linter configuration

### Manual Verification

You can also verify manually:

```bash
# Check Azure CLI
az version

# Check Bicep CLI
az bicep version

# Check Git
git --version

# Check Azure login status
az account show

# Test Bicep linter
az bicep build --file path/to/any.bicep
```

---

## IDE Setup

### Visual Studio Code (Recommended)

#### 1. Install VS Code Extensions

Open VS Code and install the following extensions:

**Required:**
- **Bicep** (Microsoft) - Provides Bicep language support
  - Extension ID: `ms-azuretools.vscode-bicep`

**Recommended:**
- **Azure Account** - Azure subscription management
  - Extension ID: `ms-vscode.azure-account`
- **Azure Resources** - View and manage Azure resources
  - Extension ID: `ms-azuretools.vscode-azureresourcegroups`
- **Azure CLI Tools** - Azure CLI command support
  - Extension ID: `ms-vscode.azurecli`

#### 2. Configure Bicep Extension

The Bicep extension automatically uses the `bicepconfig.json` file in the repository root.

To verify the extension is working:
1. Open any `.bicep` file
2. You should see syntax highlighting
3. Linter warnings/errors will appear as you type
4. Hover over resources for documentation

#### 3. Recommended VS Code Settings

Add to your workspace or user settings (`.vscode/settings.json`):

```json
{
  "editor.formatOnSave": true,
  "editor.tabSize": 2,
  "files.insertFinalNewline": true,
  "files.trimTrailingWhitespace": true,
  "[bicep]": {
    "editor.defaultFormatter": "ms-azuretools.vscode-bicep",
    "editor.formatOnSave": true,
    "editor.tabSize": 2
  }
}
```

---

## Troubleshooting

### Azure CLI Issues

**Problem:** `az: command not found`

**Solution:**
- Ensure Azure CLI is installed correctly
- macOS/Linux: Check if `/usr/local/bin` is in your `PATH`
- Windows: Restart PowerShell/Command Prompt after installation
- Verify installation: Check Azure CLI installation directory exists

**Problem:** `az login` fails or times out

**Solution:**
- Check internet connection
- Try device code login: `az login --use-device-code`
- Check firewall/proxy settings
- Clear Azure CLI cache: `az account clear`

### Bicep CLI Issues

**Problem:** `az bicep version` shows old version or error

**Solution:**
```bash
# Uninstall and reinstall Bicep
az bicep uninstall
az bicep install
az bicep version
```

**Problem:** Bicep linter not working

**Solution:**
- Verify `bicepconfig.json` exists in repository root
- Check file syntax with a JSON validator
- Run `az bicep build --file <file>` to see detailed errors
- Update Bicep CLI: `az bicep upgrade`

### Git Hooks Issues

**Problem:** Pre-commit hook not running

**Solution:**
- Verify hook is installed: `ls -la .git/hooks/pre-commit`
- Verify hook is executable: `chmod +x .git/hooks/pre-commit`
- Check if you're in a git worktree (hooks work differently)
- Try manual run: `.git/hooks/pre-commit`

**Problem:** Hook fails with permission errors

**Solution:**
```bash
chmod +x .git/hooks/pre-commit
chmod +x scripts/pre-commit-bicep
```

### VS Code Extension Issues

**Problem:** Bicep extension not providing IntelliSense

**Solution:**
- Reload VS Code window: `Ctrl/Cmd + Shift + P` → "Reload Window"
- Check extension is enabled: Extensions panel → Bicep → Ensure enabled
- Update extension to latest version
- Check Azure CLI and Bicep CLI are in PATH
- View Output panel: "Bicep" channel for errors

**Problem:** Linter warnings not showing in VS Code

**Solution:**
- Verify `bicepconfig.json` exists in workspace root
- Reload window: `Ctrl/Cmd + Shift + P` → "Reload Window"
- Check Bicep extension settings: Ensure linting is enabled
- View Problems panel: `Ctrl/Cmd + Shift + M`

---

## Next Steps

After completing this setup:

1. Review [BICEP_STANDARDS.md](BICEP_STANDARDS.md) for coding standards and conventions
2. Familiarize yourself with the repository structure (see `README.md`)
3. Read the modernization plan in `MODERNIZE_PLAN_V2.md`
4. Try building an existing Bicep template to test your setup
5. Make a small change and commit to test the pre-commit hook

---

## Additional Resources

- [Official Azure Bicep Documentation](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Azure CLI Documentation](https://learn.microsoft.com/en-us/cli/azure/)
- [Bicep Linter Rules](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/linter)
- [Bicep GitHub Repository](https://github.com/Azure/bicep)
- [VS Code Bicep Extension](https://marketplace.visualstudio.com/items?itemName=ms-azuretools.vscode-bicep)

---

## Getting Help

If you encounter issues not covered in this guide:

1. Check the [Troubleshooting](#troubleshooting) section above
2. Review existing GitHub issues in the repository
3. Consult official Azure Bicep documentation
4. Ask the team in your communication channel

---

**Last Updated:** 2025-11-16
