#
# Cookbook Name:: tomcat
# Recipe:: default
#
# Copyright 2010, Opscode, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

include_recipe "java"

tomcat_pkgs = value_for_platform(
  ["debian","ubuntu"] => {
    "default" => ["tomcat6","tomcat6-admin"]
  },
  ["centos","redhat","fedora"] => {
    "default" => ["tomcat6","tomcat6-admin-webapps"]
  },
  "default" => ["tomcat6"]
)
tomcat_pkgs.each do |pkg|
  package pkg do
    action :install
  end
end

if not node.tomcat.deploy_manager_apps
  directory "#{node.tomcat.webapp_dir}/manager" do
    action :delete
    recursive true
  end
  file "#{node.tomcat.config_dir}/Catalina/localhost/manager.xml" do
    action :delete
  end
  directory "#{node.tomcat.webapp_dir}/host-manager" do
    action :delete
    recursive true
  end
  file "#{node.tomcat.config_dir}/Catalina/localhost/host-manager.xml" do
    action :delete
  end
end

service "tomcat" do
  service_name "tomcat6"
  case node["platform"]
  when "centos","redhat","fedora"
    supports :restart => true, :status => true
  when "debian","ubuntu"
    supports :restart => true, :reload => true, :status => true
  end
  action [:enable, :start]
end

if not node.tomcat["truststore_file"].nil?
  java_options = node['tomcat']['java_options'].to_s
  java_options << " -Djavax.net.ssl.trustStore=#{node["tomcat"]["config_dir"]}/#{node["tomcat"]["truststore_file"]}"
  java_options << " -Djavax.net.ssl.trustStorePassword=#{node["tomcat"]["truststore_password"]}"

  node.set['tomcat']['java_options'] = java_options
end

case node["platform"]
when "centos","redhat","fedora"
  template "/etc/sysconfig/tomcat6" do
    source "sysconfig_tomcat6.erb"
    owner "root"
    group "root"
    mode "0644"
    notifies :restart, "service[tomcat]"
  end
else
  template "/etc/default/tomcat6" do
    source "default_tomcat6.erb"
    owner "root"
    group "root"
    mode "0644"
    notifies :restart, "service[tomcat]"
  end
end

template "/etc/tomcat6/server.xml" do
  source "server.xml.erb"
  owner "root"
  group "root"
  mode "0644"
  notifies :restart, "service[tomcat]"
end

template "/etc/tomcat6/logging.properties" do
  source "logging.properties.erb"
  owner "root"
  group "root"
  mode "0644"
  notifies :restart, "service[tomcat]"
end

if not node.tomcat.["ssl_cert_file"].nil?
  cookbook_file "#{node.tomcat.config_dir}/#{node.tomcat.ssl_cert_file}" do
    mode "0644"
  end
  cookbook_file "#{node.tomcat.config_dir}/#{node.tomcat.ssl_key_file}" do
    mode "0644"
  end
  cacerts = ""
  node.tomcat.ssl_chain_files.each do |cert|
    cookbook_file "#{node.tomcat.config_dir}/#{cert}" do
      mode "0644"
    end
    cacerts = cacerts + "#{cert} "
  end
  script "create_keystore" do
    interpreter "bash"
    cwd "#{node.tomcat.config_dir}"
    code <<-EOH
      cat #{cacerts} > cacerts.pem
      openssl pkcs12 -export \
       -inkey #{node['tomcat']['ssl_key_file']} \
       -in #{node['tomcat']['ssl_cert_file']} \
       -chain \
       -CAfile cacerts.pem \
       -password pass:#{node['tomcat']['keystore_password']} \
       -out #{node['tomcat']['keystore_file']}
    EOH
    notifies :restart, resources(:service => "tomcat")
    creates "#{node.tomcat.config_dir}/#{node.tomcat.keystore_file}"
  end
else
  execute "Create SSL certificate" do
    group node.tomcat.group
    command "#{node.tomcat.keytool} -genkeypair -keystore \"#{node.tomcat.config_dir}/#{node.tomcat.keystore_file}\" -storepass \"#{node.tomcat.keystore_password}\" -keypass \"#{node.tomcat.keystore_password}\" -dname \"#{node.tomcat.certificate_dn}\""
    umask 0007
    creates "#{node.tomcat.config_dir}/#{node.tomcat.keystore_file}"
    action :run
    notifies :restart, resources(:service => "tomcat")
  end
end

if not node.tomcat["truststore_file"].nil?
  cookbook_file "#{node['tomcat']['config_dir']}/#{node['tomcat']['truststore_file']}" do
    mode "0644"
  end
end
