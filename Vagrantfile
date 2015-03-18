#!/usr/bin/env ruby
# -*- mode: ruby -*-
# vi: set ft=ruby :
Vagrant.configure('2') do |config|
  config.vm.define 'docker' do |node|
    node.vm.hostname = 'docker'
    node.vm.box = 'chef/ubuntu-14.04'
    node.vm.provider :virtualbox do |vb|
      vb.customize [ 'modifyvm', :id, '--memory', 2048 ]
      vb.customize [ 'modifyvm', :id, '--cpus', 2 ]
      vb.customize [ 'modifyvm', :id, '--ioapic', 'on' ]
    end
  end
end
