#!/bin/bash -e
################################################################################
##  File:  etc-environment.sh
##  Desc:  Helper functions for source and modify /etc/environment
################################################################################

# NB: sed expression use '%' as a delimiter in order to simplify handling
#     values containg slashes (i.e. directory path)
#     The values containing '%' will break the functions

sudo apt-get install jq

getEtcEnvironmentVariable() {
    variable_name="$1"
    # remove `variable_name=` and possible quotes from the line
    grep "^${variable_name}=" /etc/environment |sed -E "s%^${variable_name}=\"?([^\"]+)\"?.*$%\1%"
}

addEtcEnvironmentVariable() {
    variable_name="$1"
    variable_value="$2"

    echo "$variable_name=$variable_value" | sudo tee -a /etc/environment
}

replaceEtcEnvironmentVariable() {
    variable_name="$1"
    variable_value="$2"

    # modify /etc/environemnt in place by replacing a string that begins with variable_name
    sudo sed -i -e "s%^${variable_name}=.*$%${variable_name}=\"${variable_value}\"%" /etc/environment
}

setEtcEnvironmentVariable() {
    variable_name="$1"
    variable_value="$2"

    if grep "$variable_name" /etc/environment > /dev/null; then
        replaceEtcEnvironmentVariable $variable_name $variable_value
    else
        addEtcEnvironmentVariable $variable_name $variable_value
    fi
}

prependEtcEnvironmentVariable() {
    variable_name="$1"
    element="$2"
    # TODO: handle the case if the variable does not exist
    existing_value=$(getEtcEnvironmentVariable "${variable_name}")
    setEtcEnvironmentVariable "${variable_name}" "${element}:${existing_value}"
}

appendEtcEnvironmentVariable() {
    variable_name="$1"
    element="$2"
    # TODO: handle the case if the variable does not exist
    existing_value=$(getEtcEnvironmentVariable "${variable_name}")
    setEtcEnvironmentVariable "${variable_name}" "${existing_value}:${element}"
}

prependEtcEnvironmentPath() {
    element="$1"
    prependEtcEnvironmentVariable PATH "${element}"
}

appendEtcEnvironmentPath() {
    element="$1"
    appendEtcEnvironmentVariable PATH "${element}"
}

# Process /etc/environment as if it were shell script with `export VAR=...` expressions
#    The PATH variable is handled specially in order to do not override the existing PATH
#    variable. The value of PATH variable read from /etc/environment is added to the end
#    of value of the exiting PATH variable exactly as it would happen with real PAM app read
#    /etc/environment
#
# TODO: there might be the others variables to be processed in the same way as "PATH" variable
#       ie MANPATH, INFOPATH, LD_*, etc. In the current implementation the values from /etc/evironments
#       replace the values of the current environment
reloadEtcEnvironment() {
    # add `export ` to every variable of /etc/environemnt except PATH and eval the result shell script
    eval $(grep -v '^PATH=' /etc/environment | sed -e 's%^%export %')
    # handle PATH specially
    etc_path=$(getEtcEnvironmentVariable PATH)
    export PATH="$PATH:$etc_path"
}


################################################################################
##  File:  install.sh
##  Desc:  Helper functions for installing tools
################################################################################

download_with_retries() {
# Due to restrictions of bash functions, positional arguments are used here.
# In case if you using latest argument NAME, you should also set value to all previous parameters.
# Example: download_with_retries $ANDROID_SDK_URL "." "android_sdk.zip"
    local URL="$1"
    local DEST="${2:-.}"
    local NAME="${3:-${URL##*/}}"
    local COMPRESSED="$4"

    if [[ $COMPRESSED == "compressed" ]]; then
        COMMAND="curl $URL -4 -sL --compressed -o '$DEST/$NAME'"
    else
        COMMAND="curl $URL -4 -sL -o '$DEST/$NAME'"
    fi

    echo "Downloading '$URL' to '${DEST}/${NAME}'..."
    i=20
    while [ $i -gt 0 ]; do
        ((i--))
        eval $COMMAND
        if [ $? != 0 ]; then
            sleep 30
        else
            echo "Download completed"
            return 0
        fi
    done

    echo "Could not download $URL"
    return 1
}

## Use dpkg to figure out if a package has already been installed
## Example use:
## if ! IsPackageInstalled packageName; then
##     echo "packageName is not installed!"
## fi
IsPackageInstalled() {
    dpkg -S $1 &> /dev/null
}

verlte() {
    sortedVersion=$(echo -e "$1\n$2" | sort -V | head -n1)
    [  "$1" = "$sortedVersion" ]
}

get_toolset_path() {
    echo "https://raw.githubusercontent.com/actions/virtual-environments/main/images/linux/toolsets/toolset-2004.json"
}

get_toolset_value() {
    local toolset_path=$(get_toolset_path)
    local query=$1
    echo "$(jq -r "$query" $toolset_path)"
}

isUbuntu16()
{
    lsb_release -d | grep -q 'Ubuntu 16'
}

isUbuntu18()
{
    lsb_release -d | grep -q 'Ubuntu 18'
}

isUbuntu20()
{
    lsb_release -d | grep -q 'Ubuntu 20'
}

getOSVersionLabel()
{
    lsb_release -cs
}



curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
wget -q https://packages.microsoft.com/config/ubuntu/20.04/packages-microsoft-prod.deb
sudo dpkg -i packages-microsoft-prod.deb
sudo apt-get update&&sudo add-apt-repository universe&&sudo apt-get install -y powershell

# Ubuntu 20 doesn't support EOL versions
LATEST_DOTNET_PACKAGES=$(get_toolset_value '.dotnet.aptPackages[]')
DOTNET_VERSIONS=$(get_toolset_value '.dotnet.versions[]')

# Disable telemetry
export DOTNET_CLI_TELEMETRY_OPTOUT=1

for latest_package in ${LATEST_DOTNET_PACKAGES[@]}; do
    echo "Determing if .NET Core ($latest_package) is installed"
    if ! IsPackageInstalled $latest_package; then
        echo "Could not find .NET Core ($latest_package), installing..."
        apt-get install $latest_package -y
    else
        echo ".NET Core ($latest_package) is already installed"
    fi
done

# Get list of all released SDKs from channels which are not end-of-life or preview
sdks=()
for version in ${DOTNET_VERSIONS[@]}; do
    release_url="https://dotnetcli.blob.core.windows.net/dotnet/release-metadata/${version}/releases.json"
    download_with_retries "${release_url}" "." "${version}.json"
    releases=$(cat "./${version}.json")
    sdks=("${sdks[@]}" $(echo "${releases}" | jq '.releases[]' | jq '.sdk.version'))
    sdks=("${sdks[@]}" $(echo "${releases}" | jq '.releases[]' | jq '.sdks[]?' | jq '.version'))
    rm ./${version}.json
done

sortedSdks=$(echo ${sdks[@]} | tr ' ' '\n' | grep -v preview | grep -v rc | grep -v display | cut -d\" -f2 | sort -r | uniq -w 5)

extract_dotnet_sdk() {
    local ARCHIVE_NAME="$1"
    set -e
    dest="./tmp-$(basename -s .tar.gz $ARCHIVE_NAME)"
    echo "Extracting $ARCHIVE_NAME to $dest"
    mkdir "$dest" && tar -C "$dest" -xzf "$ARCHIVE_NAME"
    rsync -qav --remove-source-files "$dest/shared/" /usr/share/dotnet/shared/
    rsync -qav --remove-source-files "$dest/host/" /usr/share/dotnet/host/
    rsync -qav --remove-source-files "$dest/sdk/" /usr/share/dotnet/sdk/
    rm -rf "$dest" "$ARCHIVE_NAME"
}

# Download/install additional SDKs in parallel
export -f download_with_retries
export -f extract_dotnet_sdk

parallel --jobs 0 --halt soon,fail=1 \
    'url="https://dotnetcli.blob.core.windows.net/dotnet/Sdk/{}/dotnet-sdk-{}-linux-x64.tar.gz"; \
    download_with_retries $url' ::: "${sortedSdks[@]}"

find . -name "*.tar.gz" | parallel --halt soon,fail=1 'extract_dotnet_sdk {}'

# NuGetFallbackFolder at /usr/share/dotnet/sdk/NuGetFallbackFolder is warmed up by smoke test
# Additional FTE will just copy to ~/.dotnet/NuGet which provides no benefit on a fungible machine
setEtcEnvironmentVariable DOTNET_SKIP_FIRST_TIME_EXPERIENCE 1
setEtcEnvironmentVariable DOTNET_NOLOGO 1
setEtcEnvironmentVariable DOTNET_MULTILEVEL_LOOKUP 0
prependEtcEnvironmentPath '$HOME/.dotnet/tools'