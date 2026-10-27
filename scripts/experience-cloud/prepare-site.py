#!/usr/bin/env python3
"""Prepare environment-specific Experience Cloud metadata outside the source tree."""
import argparse
import json
import shutil
import xml.etree.ElementTree as ET
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--site-admin', required=True, help='Active internal Salesforce username in the target org')
parser.add_argument('--sender-email', required=True)
parser.add_argument('--output', required=True, type=Path, help='New directory outside the repository')
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
output = args.output.resolve()
if output == root or root in output.parents:
    parser.error('Output must be outside the repository.')
if output.exists():
    parser.error('Output directory already exists; choose a new directory.')
source = root / 'force-app/main/default'
target = output / 'force-app/main/default'
target.mkdir(parents=True)
for directory in ('sites', 'networks', 'digitalExperiences', 'digitalExperienceConfigs'):
    shutil.copytree(source / directory, target / directory)
profiles = target / 'profiles'
profiles.mkdir()
shutil.copy2(source / 'profiles/SmartReturn Customer Portal Profile.profile-meta.xml', profiles)
namespace = 'http://soap.sforce.com/2006/04/metadata'
ET.register_namespace('', namespace)
for file, values in (
    (target / 'sites/SmartReturn_Customer_Portal.site-meta.xml', {
        'siteAdmin': args.site_admin,
        'siteGuestRecordDefaultOwner': args.site_admin,
    }),
    (target / 'networks/SmartReturn Customer Portal.network-meta.xml', {
        'emailSenderAddress': args.sender_email,
    }),
):
    tree = ET.parse(file)
    for field, value in values.items():
        tree.getroot().find(f'{{{namespace}}}{field}').text = value
    tree.write(file, encoding='UTF-8', xml_declaration=True)
(output / 'sfdx-project.json').write_text(json.dumps({
    'packageDirectories': [{'path': 'force-app', 'default': True}],
    'namespace': '',
    'sourceApiVersion': '67.0',
}, indent=2) + '\n')
print(output)
