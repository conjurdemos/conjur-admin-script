# Conjur Admin Script
A powerful automation script for managing and interacting with CyberArk Conjur.
This repository provides an easy-to-use tool for common administrative tasks.

## Certification level
![](https://img.shields.io/badge/Certification%20Level-Certified-6C757D?link=https://github.com/cyberark/community/blob/master/Conjur/conventions/certification-levels.md)

This repo is a **Certified** level project. It's been reviewed by CyberArk to verify that it will securely
work with CyberArk Conjur Enterprise as documented. In addition, CyberArk offers Enterprise-level support for these features. For
more detailed  information on our certification levels, see [our community guidelines](https://github.com/cyberark/community/blob/master/Conjur/conventions/certification-levels.md#community).

## Requirements

Specific functions such as "Export the effective policy" requires Conjur Open Source / Enterprise 13.4 or higher.
Other functions can work with previous versions.

## Usage instructions

```
git clone https://github.com/conjurdemos/conjur-admin-script.git
cd conjur-admin-script
bash conjur_admin.sh
```
Menu Options:

🛠1. Collect Data From Nodes

 Connects to each cluster node and executes an autogenerated bash script file, checker.sh. The output is saved in conjur_checker.log. This script performs a series of checks on each node, including:

    Configuration Files:
        /etc/hosts
        /etc/hostname
        /etc/resolv.conf
        /etc/redhat-release

    System Information:
        Kernel version (uname -a)
        SELinux status
        Podman version

    System Health:
        Filesystem status
        Folder permissions
        Info endpoint
        Health endpoint

🔍2. Cluster Consistency Check

 Analyzes the conjur_checker.log file (automatically runs Collect Data From Nodes if the file is not found) and performs comparisons of key packages and configurations to ensure consistency across all nodes in the Conjur HA Cluster.

📂3. Export the Effective Policy

 Authenticates with the Conjur API and extracts the loaded policies from the Conjur database. The policies are then organized into a folder structure on the local filesystem, mirroring the database structure.

🔓4. Fetch Secret Values in Bulk

 Fetches all secrets accessible to the currently logged-in user. Caution: The fetched secrets are displayed in plain text on the standard output. Handle with care to avoid exposing sensitive information.

📋5. Conjur Objects List

 Authenticates with the Conjur API and generates a summary of the number of objects loaded into Conjur, including users, policies, groups, and other entities.

🗂6. Conjur Variable Show

 Provides an interactive menu listing the variables loaded into Conjur. You can choose to view metadata information about each variable or reveal the value itself.

👤7. Grant Read Permissions

 Assigns read permissions to a host, which is created at the root level if it does not exist. If the host already exists, permissions are granted. This action applies to all objects in conjur, ensuring that it has the necessary access for auditing or other read-only operations.

## Contributing

We welcome contributions of all kinds to this repository. For instructions on how to get started and descriptions
of our development workflows, please see our [contributing guide](CONTRIBUTING.md).

## License

Copyright (c) 2024 CyberArk Software Ltd. All rights reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

For the full license text see [`LICENSE`](LICENSE).
