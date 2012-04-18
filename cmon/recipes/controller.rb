#
# Cookbook Name:: cmon
# Recipe:: controller
#
# Copyright 2012, Severalnines AB.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

cmon_config = data_bag_item('controller', 'config')
node['cmon']['remote']['mysql_hostname'] = node['ipaddress']
node['cmon']['mode']['controller']  = cmon_config['mode']

cmon_package=cmon_config['cmon_package_' + node['kernel']['machine']]
Chef::Log.info "Downloading #{cmon_package}.tar.gz"
remote_file "#{Chef::Config[:file_cache_path]}/cmon.tar.gz" do
  source "http://www.severalnines.com/downloads/cmon/" + cmon_package + ".tar.gz"
  action :create_if_missing
end

# install cmon in /usr/local/cmon as default
directory node['cmon']['install_dir_cmon'] do
  owner "root"
  mode "0755"
  action :create
  recursive true
end

bash "untar-cmon-package" do
  user "root"
  code <<-EOH
    rm -rf #{node['cmon']['install_dir_cmon']}/cmon
    zcat #{Chef::Config[:file_cache_path]}/cmon.tar.gz | tar xf - -C #{node['cmon']['install_dir_cmon']}
    ln -s #{node['cmon']['install_dir_cmon']}/#{cmon_package} #{node['cmon']['install_dir_cmon']}/cmon
  EOH
	not_if { File.directory? "#{node['cmon']['install_dir_cmon']}/cmon" }
end

execute "controller-create-db-schema" do
  command "#{node['cmon']['mysql']['bin_dir']}/mysql -uroot -p#{node['cmon']['local']['mysql_password']} < #{node['cmon']['install_dir_cmon']}/cmon/sql/cmon_db.sql"
  action :run
end

execute "controller-import-tables" do
  command "#{node['cmon']['mysql']['bin_dir']}/mysql -uroot -p#{node['cmon']['local']['mysql_password']} < #{node['cmon']['install_dir_cmon']}/cmon/sql/cmon_data.sql"
  action :run
end

execute "controller-install-privileges" do
  command "#{node['cmon']['mysql']['bin_dir']}/mysql -uroot -p#{node['cmon']['local']['mysql_password']} < #{node['cmon']['install_dir_cmon']}/cmon/sql/cmon_controller_grants.sql"
  action :nothing
end

Chef::Log.info "Create controller grants"
template "cmon.controller.grants.sql" do
  path "#{node['cmon']['install_dir_cmon']}/cmon/sql/cmon_controller_grants.sql"
  source "cmon.controller.grants.sql.erb"
  owner "root"
  group "root"
  mode "0644"
  notifies :run, resources(:execute => "controller-install-privileges"), :immediately
end


agents = data_bag_item('agent', 'config')
hosts = agents['hosts']
host_list = ""
hosts.each do |h|
 host_list << h + " "
end

bash "create-agent-grants" do
  user "root"
  code <<-EOH
    for h in #{host_list}
    do
      echo "GRANT SUPER ON *.* TO 'cmon'@'$h' IDENTIFIED BY '#{node['cmon']['cmon_password']}';" >> #{node['cmon']['install_dir_cmon']}/cmon/sql/cmon_controller_agent_grants.sql
      echo "GRANT INSERT,UPDATE,DELETE,SELECT ON cmon.* TO 'cmon'@'$h' IDENTIFIED BY '#{node['cmon']['cmon_password']}';" >> #{node['cmon']['install_dir_cmon']}/cmon/sql/cmon_controller_agent_grants.sql
    done
  EOH
end

execute "controller-grant-agents" do
  command "#{node['cmon']['mysql']['bin_dir']}/mysql -uroot -p#{node['cmon']['local']['mysql_password']} < #{node['cmon']['install_dir_cmon']}/cmon/sql/cmon_controller_agent_grants.sql"
  action :run
end


execute "install-core-scripts" do
  command "cp #{node['cmon']['install_dir_cmon']}/cmon/bin/cmon_* /usr/bin/"
  action :run
end


directory node['cmon']['misc']['lock_dir'] do
  owner "root"
  mode "0755"
  action :create
  recursive true
end

service "cmon" do
  supports :restart => true, :start => true, :stop => true, :reload => true
  action :nothing
end 

template "cmon.controller.cnf" do
  path "#{node['cmon']['install_configpath']}/cmon.cnf"
  source "cmon.controller.cnf.erb"
  owner "root"
  group "root"
  mode "0644"
  notifies :restart, resources(:service => "cmon")
end

cookbook_file "/etc/init.d/cmon" do
  backup false
  owner "root"
  group "root"
  mode "0755"
  source "etc/init.d/cmon"
  notifies :restart, resources(:service => "cmon")
end

service "cmon" do
  supports :restart => true, :start => true, :stop => true, :reload => true
  action [:enable, :start]
end 
