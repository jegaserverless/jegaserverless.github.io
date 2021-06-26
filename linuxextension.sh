curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
wget -q https://packages.microsoft.com/config/ubuntu/20.04/packages-microsoft-prod.deb
sudo dpkg -i packages-microsoft-prod.deb
sudo apt-get update&&sudo add-apt-repository universe&&sudo apt-get install -y powershell
sudo snap install dotnet-sdk --classic --channel=5.0
sudo snap install dotnet-sdk --classic --channel=3.1
sudo snap install dotnet-sdk --classic --channel=2.1
sudo snap alias dotnet-sdk.dotnet dotnet