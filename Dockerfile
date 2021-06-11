# use Debian since Alpine has problematic DNS causing issues on Kubernetes cluters
FROM debian:10.7
SHELL ["/bin/bash", "-c"]
RUN apt-get --yes update -y && apt-get upgrade --yes && apt-get --yes install apt-utils && apt-get --yes autoremove
RUN echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections
RUN apt-get --yes install  curl | grep -q "OK" || echo "Error occured during installation of curl"
RUN apt-get install --yes dnsutils && apt-get --yes install nmap && apt-get -y install netcat-openbsd
RUN apt-get -y install wget && wget https://packages.microsoft.com/config/debian/10/packages-microsoft-prod.deb
RUN dpkg -i packages-microsoft-prod.deb && apt-get update && apt-get install -y powershell
RUN install_log=$(apt-get --yes install default-mysql-client); \
    if [[ $? != 0 ]]; then echo "Error occurred during installation of MySQL client: $install_log" >> tests.out; fi;

COPY ./http-endpoint-tests.ps1 /

ENTRYPOINT ["pwsh", "-command"]