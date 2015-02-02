#This class is intended to deploy VPNaaS in HA mode.

class vpnaas::ha {

  include vpnaas::params
  include neutron::params

  $fuel_settings      = parseyaml($astute_settings_yaml)
  $access_hash        = $fuel_settings['access']
  $neutron_config     = $fuel_settings['quantum_settings']
  $primary_controller = $fuel_settings['role'] ? { 'primary-controller'=>true, default=>false }

  $debug              = true
  $verbose            = true
  $syslog             = $fuel_settings['use_syslog'] ? { default=>true }
  $plugin_config      = '/etc/neutron/l3_agent.ini'

  file {'q-agent-cleanup.py':
    path   => '/usr/bin/q-agent-cleanup.py',
    mode   => '0755',
    owner  => root,
    group  => root,
    source => "puppet:///modules/vpnaas/q-agent-cleanup.py",
  }

  file { "${vpnaas::params::vpn_agent_ocf_file}":
    mode   => 644,
    owner  => root,
    group  => root,
    source => "puppet:///modules/vpnaas/ocf/neutron-agent-vpn"
  }

  class {'vpnaas::common':}

  class {'vpnaas::agent':
    manage_service => true,
    enabled        => false,
  }

  service {'p_neutron-l3-agent':
    enable     => true,
    ensure     => stopped,
    hasstatus  => true,
    hasrestart => true,
    provider   => 'pacemaker',
  }

  Service['p_neutron-l3-agent'] -> Class['vpnaas::agent']

  $csr_metadata        = undef
  $csr_complex_type    = 'clone'
  $csr_ms_metadata     = { 'interleave' => 'true' }

  cluster::corosync::cs_with_service {'vpn-and-ovs':
    first   => "clone_p_${neutron::params::ovs_agent_service}",
    second  => "clone_p_${neutron::params::vpnaas_agent_service}"
  }

  cluster::corosync::cs_service {'vpn':
    ocf_script      => 'neutron-agent-vpn',
    csr_parameters  => {
      'debug'           => $debug,
      'syslog'          => $syslog,
      'plugin_config'   => $plugin_config,
      'os_auth_url'     => "http://${fuel_settings['management_vip']}:35357/v2.0/",
      'tenant'          => 'services',
      'username'        => undef,
      'password'        => $neutron_config['keystone']['admin_password'],
      'multiple_agents' => $multiple_agents,
    },
    csr_metadata        => $csr_metadata,
    csr_complex_type    => $csr_complex_type,
    csr_ms_metadata     => $csr_ms_metadata,
    csr_mon_intr        => '20',
    csr_mon_timeout     => '10',
    csr_timeout         => '60',
    service_name        => $neutron::params::vpnaas_agent_service,
    package_name        => $neutron::params::vpnaas_agent_package,
    service_title       => 'neutron-vpnaas-service',
    primary             => $primary_controller,
    hasrestart          => false,
  }

  File['q-agent-cleanup.py']                        -> Cluster::Corosync::Cs_service["vpn"]
  File["${vpnaas::params::vpn_agent_ocf_file}"]     -> Cluster::Corosync::Cs_service["vpn"] ->
  Cluster::Corosync::Cs_with_service['vpn-and-ovs'] -> Class['vpnaas::common']
}
