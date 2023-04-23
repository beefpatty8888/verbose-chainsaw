# verbose-chainsaw
Basic Wordpress site in AWS

In the dynamicInventory.py, the hashbang will be different for the path to python3 for Windows and Linux hosts.

`ansible-inventory -i ./dynamicInventory.py --list`

`ansible -v -i ./dynamicInventory.py webservers -m raw -a "ls -latr" --list-hosts`

# terraform infrastructure

`terraform init`

`terraform plan`
