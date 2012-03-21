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
    if request.post?
      errorMsg = "GET is required to access get_kickstart"
      Rails.logger.warn errorMsg
      return render :text=>"#{errorMsg}\n", :cache=>false, :status=>500
    end

    node = NodeObject.find_nodes_by_name( params[:name] )[0]
    @admin_node=NodeObject.find_admin_node

    template_file = ""
    if( node.installation_drives_set == NodeObject::FrontDrives or
        node.software_raid_set == NodeObject::NoRaid )

      disks = []
      if( node.installation_drives_set == NodeObject::FrontDrives  )
        disks = node.get_front_disks
        Rails.logger.debug "Found #{disks.length} front disks"
      else
        disks = node.get_internal_disks
        Rails.logger.debug "Found #{disks.length} internal disks"
      end

      disks.sort! { |disk1,disk2| disk1.basename <=> disk2.basename }
      drive = disks[0]

      # Set up substitution parameters for the renderer
      @installation_drives = drive.basename
      @ignore_drives = get_ignore_drives( [drive] )

      template_file = "/opt/dell/crowbar_framework/app/views/barclamp/provisioner/kickstart_noraid.template.erb"
    else
      disks = node.get_internal_disks
      Rails.logger.debug "Found #{disks.length} internal disks"

      disks.sort! { |disk1,disk2| disk1.basename <=> disk2.basename }

      # Set up substitution parameters for the renderer
      @installation_drives = ""
      disk_number=1
      disks.each do |disk|
        @installation_drives += disk.basename

        if disk_number < disks.length 
          @installation_drives += ","
        end
        
        disk_number = disk_number+1
      end

      @ignore_drives = get_ignore_drives( disks )
      @rhel5_partitions = get_partition_lines( disks, "ext3" )
      @rhel6_partitions = get_partition_lines( disks, "ext4" )

      # Generate the full template
      template_file = "/opt/dell/crowbar_framework/app/views/barclamp/provisioner/kickstart_raid.template.erb"
    end

    # Send the result back to the caller
    render template_file, :cache => false
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
