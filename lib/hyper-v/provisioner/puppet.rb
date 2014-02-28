#-------------------------------------------------------------------------
# Copyright (c) Microsoft Open Technologies, Inc.
# All Rights Reserved. Licensed under the MIT License.
#--------------------------------------------------------------------------
require "fileutils"
require "tempfile"
module VagrantPlugins
  module HyperV
    module Provisioner
      class Puppet
        attr_reader :provisioner
        def initialize(env, provisioner)
          @env = env
          @provisioner = provisioner
        end

        def provision_for_windows
          options = [config.options].flatten
          @module_paths = provisioner.instance_variable_get("@module_paths")
          @hiera_config_path = provisioner.instance_variable_get("@hiera_config_path")
          @manifest_file = provisioner.instance_variable_get("@manifest_file")

          module_paths = @module_paths.map { |_, to| to }
          if !@module_paths.empty?
            # Prepend the default module path
            module_paths.unshift("/ProgramData/PuppetLabs/puppet/etc/modules")

            # Add the command line switch to add the module path
            options << "--modulepath '#{module_paths.join(':')}'"
          end

          if @hiera_config_path
            options << "--hiera_config=#{@hiera_config_path}"
          end

          options << "--manifestdir #{provisioner.manifests_guest_path}"
          options << "--detailed-exitcodes"
          options << @manifest_file
          options = options.join(" ")

          # Build up the custom facts if we have any
          facter = ""
          if !config.facter.empty?
            facts = []
            config.facter.each do |key, value|
              facts << "FACTER_#{key}='#{value}'"
            end

            facter = "#{facts.join(" ")} "
          end

          command = "#{facter}puppet apply #{options}"
          if config.working_directory
            command = "cd #{config.working_directory} && #{command}"
          end

          @env[:ui].info I18n.t("vagrant.provisioners.puppet.running_puppet",
                                      :manifest => config.manifest_file)
          file = Tempfile.new(['vagrant-puppet-powershell', '.ps1'])
          begin
            file.write command
            file.fsync
            file.close
            source_path = file.path
          ensure
            file.close
          end

          # Upload the file to Guest VM
          fixed_upload_path = "/tmp/vagrant-puppet/vagrant-puppet-powershell.ps1"
          options = { :host_path => source_path.gsub("/","\\"),
                     :guest_path => fixed_upload_path.gsub("/","\\"),
                     :vm_id => @env[:machine].id }
          begin
            response = @env[:machine].provider.driver.execute('upload_file.ps1', options)

            @env[:ui].info "Executing puppet script in Guest"
            # Execute the file from remote location
            ssh_info = @env[:machine].ssh_info
            options = { :guest_ip => ssh_info[:host],
                       :username => ssh_info[:username],
                       :path => fixed_upload_path,
                       :vm_id => @env[:machine].id,
                       :password => "vagrant" }

            @env[:machine].provider.driver.execute('execute_remote_file.ps1', options) do |type, data|
              if type == :stdout || type == :stderr
                @env[:ui].info data
              end
            end
          rescue Error::SubprocessError => e
            @env[:ui].info e.message
          end
        end

        protected

        def config
          provisioner.config
        end

      end
    end
  end
end
