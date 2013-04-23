#
# Cookbook Name:: sensu
# Recipe:: _linux
#
# Copyright 2012, Sonian Inc.
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

package_options = ""

case node.platform_family
when "debian"
  package_options = '--force-yes -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confnew"'

  include_recipe "apt"

  apt_repository "sensu" do
    uri "http://repos.sensuapp.org/apt"
    key "http://repos.sensuapp.org/apt/pubkey.gpg"
    distribution "sensu"
    components node.sensu.use_unstable_repo ? ["unstable"] : ["main"]
    action :add
  end

  apt_preference "sensu" do
    pin "version #{node.sensu.version}"
    pin_priority "700"
  end
when "rhel"
  include_recipe "yum"

  yum_repository "sensu" do
    description "sensu monitoring"
    repo = node.sensu.use_unstable_repo ? "yum-unstable" : "yum"
    url "http://repos.sensuapp.org/#{repo}/el/#{node['platform_version'].to_i}/$basearch/"
    action :add
  end
when "fedora"
  include_recipe "yum"

  rhel_version_equivalent = case node.platform_version.to_i
  when 6..11  then 5
  when 12..18 then 6
  # TODO: 18+ will map to rhel7 but we don't have sensu builds for that yet
  else
    raise "I don't know how to map fedora version #{node['platform_version']} to a RHEL version. aborting"
  end

  yum_repository "sensu" do
    description "sensu monitoring"
    repo = node.sensu.use_unstable_repo ? "yum-unstable" : "yum"
    url "http://repos.sensuapp.org/#{repo}/el/#{rhel_version_equivalent}/$basearch/"
    action :add
  end
end

package "sensu" do
  version node.sensu.version
  options package_options
  notifies :create, "ruby_block[sensu_service_trigger]", :immediately
end

template "/etc/default/sensu" do
  source "sensu.default.erb"
end

if node.sensu.use_embedded_runit

  sensu_ctl = ::File.join(node.sensu.embedded_directory,'bin','sensu-ctl')

  execute "configure_sensu_embedded_runit" do
    command "#{sensu_ctl} configure"
    not_if "#{sensu_ctl} configured?"
  end

  # Keep on trying till the job is found :(
  execute "wait_for_sensu_embedded_runit" do
    command "#{sensu_ctl} configured?"
    retries 30
  end

  # Replace packaged init scripts with links to runit
  %w{ client server api dashboard }.each do |svc|
    file "/etc/init.d/sensu-#{svc}" do
      action :delete
      not_if {::File.symlink?("/etc/init.d/sensu-#{svc}")}
    end

    link "/etc/init.d/sensu-#{svc}" do
      to ::File.join(node.sensu.embedded_directory,'embedded','bin','sv')
    end
  end
end
