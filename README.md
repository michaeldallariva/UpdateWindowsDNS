############################################################################################################################################################################################################################################################
# Update Windows DNS settings
# GitHub link : https://github.com/michaeldallariva
# Version : v1.0
# Author : Michael DALLA RIVA, with the help of some AI
# 27 Feb 2025
#
# Purpose:
# Useful when changing DNS servers in a corporate network for clients and servers not set to use DHCP.
# 
# To be deplolyed using your central PowerShell script solution such as SCCM etc
# 
# 1. Checks all network interfaces if they are set to DHCP - IF DHCP enabled : no change will occur
# 2. If a network interface is set to fixed IP, it will update the 2 DNS entries if they do not match the new DNS IP addresses variables below.
# 3. If a network interface is set to fixed IP but DNS entries are not populated (blank), it will not add the 2 DNS server's IP addresses below. This is useful for hosts with multiple network interfaces and/or in isolated VLAN/DMZ.
#
# License :
# Feel free to use for any purpose, personal or commercial.
#
############################################################################################################################################################################################################################################################
