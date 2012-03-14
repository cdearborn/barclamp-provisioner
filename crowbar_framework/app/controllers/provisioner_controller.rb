# Copyright 2011, Dell 
# 
# Licensed under the Apache License, Version 2.0 (the "License"); 
# you may not use this file except in compliance with the License. 
# You may obtain a copy of the License at 
# 
#  http://www.apache.org/licenses/LICENSE-2.0 
# 
# Unless required by applicable law or agreed to in writing, software 
# distributed under the License is distributed on an "AS IS" BASIS, 
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. 
# See the License for the specific language governing permissions and 
# limitations under the License. 
# 

class ProvisionerController < BarclampController
  DriveLetters="abcdefghijklmnopqrstuvwxyz"

  def initialize
    @service_object = ProvisionerService.new logger
  end

  def get_kickstart
    node = NodeObject.find_nodes_by_name( params[:name] )[0]

    customized_kickstart = ""
    if( node.installation_drives_set == NodeObject::FrontDrives or
        node.software_raid_set == NodeObject::NoRaid )

      disks = []
      if( node.installation_drives_set == NodeObject::FrontDrives  )
        disks = node.get_front_disks
      else
        disks = node.get_internal_disks
      end

      disks.sort! { |disk1,disk2| disk1.basename <=> disk2.basename }
      drive = disks[0]
      ignore_drives = get_ignore_drives( [drive] )

      customized_kickstart = IO.read("/opt/dell/crowbar_framework/app/views/barclamp/provisioner/kickstart_noraid.template" )
      customized_kickstart.gsub!("INSTALLATION_DRIVE", drive.basename)
      customized_kickstart.gsub!("IGNORE_DRIVES", ignore_drives)
      customized_kickstart += "\n"
    else
      disks = node.get_internal_disks
      disks.sort! { |disk1,disk2| disk1.basename <=> disk2.basename }

      # Build up comma separated string of drives
      drive_names = ""
      disk_number=1
      disks.each do |disk|
        drive_names += disk.basename

        if disk_number < disks.length 
          drive_names += ","
        end
        
        disk_number = disk_number+1
      end

      ignore_drives = get_ignore_drives( disks )

      # Generate the full template
      customized_kickstart = IO.read("/opt/dell/crowbar_framework/app/views/barclamp/provisioner/kickstart_raid_1.template" )

      customized_kickstart += get_partition_lines( disks, "ext4" )

      customized_kickstart += IO.read("/opt/dell/crowbar_framework/app/views/barclamp/provisioner/kickstart_raid_2.template" )

      customized_kickstart += get_partition_lines( disks, "ext3" )

      customized_kickstart += IO.read("/opt/dell/crowbar_framework/app/views/barclamp/provisioner/kickstart_raid_3.template" )

      customized_kickstart.gsub!("INSTALLATION_DRIVES", drive_names)
      customized_kickstart.gsub!("IGNORE_DRIVES", ignore_drives)
    end

    # Send the result back to the caller
    render :inline => "customized kickstart: #{customized_kickstart}", :cache => false
  end 


  def get_ignore_drives drives
      scsi_ignore_drives = ""
      sata_ignore_drives = ""
      DriveLetters.each_char do |drive_letter|
        found=false
        drives.each do |drive|
          drive_name=drive.basename
          if drive_name[drive_name.length-1,1] == drive_letter
            found=true
            break
          end
        end

        next if found

        scsi_ignore_drives += "sd#{drive_letter},"
        sata_ignore_drives += "hd#{drive_letter},"
      end

      ignore_drives="#{scsi_ignore_drives}#{sata_ignore_drives}"
      ignore_drives.chomp! ","
      ignore_drives
  end

  def get_partition_lines( disks, fs_type )
      partition_lines=""

      disk_number=1
      boot_partitions=""
      swap_partitions=""
      disks.each do |disk|

        boot_partition_name = "raid.#{disk_number}0"
        swap_partition_name = "raid.#{disk_number}1"

        partition_lines += "part #{boot_partition_name}    --size 100         --asprimary --ondrive=#{disk.basename}\n"
        partition_lines += "part #{swap_partition_name}    --size 1   --grow  --asprimary --ondrive=#{disk.basename}\n"

        boot_partitions += boot_partition_name
        boot_partitions += " " if disk_number < disks.length

        swap_partitions += swap_partition_name
        swap_partitions += " " if disk_number < disks.length

        disk_number += 1
      end

      # Generate the raid lines
      partition_lines += "raid /boot --fstype #{fs_type} --device=md0 --level=RAID1 #{boot_partitions}\n"
      partition_lines += "raid pv.01 --fstype #{fs_type} --device=md1 --level=RAID1 #{swap_partitions}\n"
      partition_lines
  end
end
