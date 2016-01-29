#!/usr/bin/env ruby
# -*- mode: ruby -*-
# vi: set ft=ruby :
Vagrant.configure('2') do |config|
  config.vm.provider :virtualbox do |vbox|
    vbox.customize [ 'modifyvm', :id, '--memory', 4096 ]
    vbox.customize [ 'modifyvm', :id, '--cpus', 4 ]
  end

  config.vm.define 'test' do |node|
    node.vm.box = 'bento/ubuntu-14.04'
    node.vm.hostname = 'test'
    node.vm.provision :shell, inline: <<-END
      apt-get update
      apt-get install -y libtool libsnappy1 libsnappy-dev
      cd /vagrant/pkg
      dpkg -i franz*.deb
      franz -v
    END
  end
end