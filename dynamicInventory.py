#!/opt/homebrew/bin/python3

import argparse
import json
import sys

import boto3


ansibleMetadata={"_meta":{"hostvars":{}},"webservers":{"hosts":[]},"otherHosts":{"hosts":[]}}

session=boto3.Session(profile_name='default')

regions=session.get_available_regions('ec2','aws')
 

def getHostDetails(hostID,hostIP):
   
  metadataHostVars = ansibleMetadata["_meta"]["hostvars"]
  metadataHostVars[hostID] = {}

  metadataHostVars[hostID]["ansible_host"] =  hostIP
  metadataHostVars[hostID]["ansible_ssh_private_key_file"] = "~/.ssh/id_rsa"
  metadataHostVars[hostID]["ansible_ssh_user"] = "ubuntu"
 
  ansibleMetadata["webservers"]["hosts"].append(str(hostID))

def listEC2Hosts():

   for region in regions:
    if 'us-' in region:
      ec2 = session.resource('ec2',region_name=region)
      ec2instances = ec2.instances.all()
      if ec2instances: 
        for instance in ec2instances:
          tagName=""
          if instance.tags:
            for tag in instance.tags:
              
              if tag["Key"] == "Name":
                tagName=tag["Value"]
          else:
            #if there are no tags at all, then it remains blank
            tagName=""

          getHostDetails(str(instance.id),str(instance.public_ip_address))

   
   #append the global Ansible connection vars for the otherHosts group.
   ansibleMetadata["otherHosts"]["vars"] = {}
   ansibleMetadata["otherHosts"]["vars"]["ansible_ssh_user"] = "ubuntu"
   ansibleMetadata["otherHosts"]["vars"]["ansible_ssh_private_key_file"] = "~/.ssh/id_rsa" 
 
def main(): 
      
     parser = argparse.ArgumentParser()
     parser.add_argument("--list", help="list all webserver hosts", action="store_true")
     args = parser.parse_args()

     if args.list == True:
       listEC2Hosts()
       print (json.dumps (ansibleMetadata))
 
if __name__ == '__main__':
    main()

