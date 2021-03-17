require 'spec_helper'
require 'helm_template_helper'
require 'yaml'

describe 'checkConfig template' do
  let(:check) do
    Open3.capture3(HelmTemplate.helm_template_call(release_name: 'gitlab-checkconfig-test'),
                   chdir: File.join(__dir__, '..', '..'),
                   stdin_data: YAML.dump(values))
  end

  let(:stdout) { check[0] }
  let(:stderr) { check[1] }
  let(:exit_code) { check[2].to_i }

  let(:default_required_values) do
    { 'certmanager-issuer' => { 'email' => 'test@example.com' } }
  end

  shared_examples 'config validation' do |success_description: '', error_description: ''|
    context success_description do
      let(:values) { success_values }

      it 'succeeds', :aggregate_failures do
        expect(exit_code).to eq(0)
        expect(stdout).to include('name: gitlab-checkconfig-test')
        expect(stderr).to be_empty
      end
    end

    context error_description do
      let(:values) { error_values }

      it 'returns an error', :aggregate_failures do
        expect(exit_code).to be > 0
        expect(stdout).to be_empty
        expect(stderr).to include(error_output)
      end
    end
  end

  # This is not actually in _checkConfig.tpl, but it uses `required`, so
  # acts in a similar way
  describe 'certmanager-issuer.email' do
    let(:success_values) { default_required_values }
    let(:error_values) { {} }
    let(:error_output) { 'Please set certmanager-issuer.email' }

    include_examples 'config validation',
                     success_description: 'when set',
                     error_description: 'when unset'
  end

  describe 'gitaly.tls without Praefect' do
    let(:success_values) do
      {
        'global' => {
          'gitaly' => {
            'enabled' => 'true',
            'tls' => { 'enabled' => true, 'secretName' => 'example-tls' }
          }
        }
      }.merge(default_required_values)
    end

    let(:error_values) do
      {
        'global' => {
          'gitaly' => {
            'enabled' => 'true',
            'tls' => { 'enabled' => true }
          }
        }
      }.merge(default_required_values)
    end

    let(:error_output) { 'global.gitaly.tls.secretName not specified' }

    include_examples 'config validation',
                     success_description: 'when TLS is enabled correctly',
                     error_description: 'when TLS is enabled but there is no certificate'
  end

  describe 'gitaly.tls with Praefect' do
    let(:success_values) do
      {
        'global' => {
          'praefect' => {
            'enabled' => true,
            'virtualStorages' => [
              { 'name' => 'default', 'gitalyReplicas' => 3,
                'maxUnavailable' => 2, 'tlsSecretName' => 'gitaly-default-tls' },
              { 'name' => 'vs1', 'gitalyReplicas' => 2,
                'maxUnavailable' => 1, 'tlsSecretName' => 'gitaly-vs2-tls' }
            ]
          },
          'gitaly' => {
            'enabled' => 'true',
            'tls' => { 'enabled' => true }
          }
        }
      }.merge(default_required_values)
    end

    let(:error_values) do
      {
        'global' => {
          'praefect' => {
            'enabled' => true,
            'virtualStorages' => [
              { 'name' => 'default', 'gitalyReplicas' => 3,
                'maxUnavailable' => 2, 'tlsSecretName' => 'gitaly-default-tls' },
              { 'name' => 'vs2', 'gitalyReplicas' => 2,
                'maxUnavailable' => 1 }
            ]
          },
          'gitaly' => {
            'enabled' => 'true',
            'tls' => { 'enabled' => true }
          }
        }
      }.merge(default_required_values)
    end

    let(:error_output) { 'global.praefect.virtualStorages[1].tlsSecretName not specified (\'vs2\')' }

    include_examples 'config validation',
                     success_description: 'when TLS is enabled correctly',
                     error_description: 'when TLS is enabled but there is no certificate'
  end

  describe 'sidekiq.queues.mixed' do
    let(:success_values) do
      {
        'gitlab' => {
          'sidekiq' => {
            'pods' => [
              { 'name' => 'valid-1', 'queues' => 'merge' },
              { 'name' => 'valid-2', 'negateQueues' => 'post_receive' }
            ]
          }
        }
      }.merge(default_required_values)
    end

    let(:error_values) do
      {
        'gitlab' => {
          'sidekiq' => {
            'pods' => [
              { 'name' => 'invalid-1', 'queues' => 'merge', 'negateQueues' => 'post_receive' },
              { 'name' => 'invalid-2', 'queues' => 'merge', 'negateQueues' => 'post_receive' }
            ]
          }
        }
      }.merge(default_required_values)
    end

    let(:error_output) { '`negateQueues` is not usable if `queues` is provided' }

    include_examples 'config validation',
                     success_description: 'when Sidekiq pods use either queues or negateQueues',
                     error_description: 'when Sidekiq pods use both queues and negateQueues'
  end

  describe 'sidekiq.queues.cluster' do
    let(:success_values) do
      {
        'gitlab' => {
          'sidekiq' => {
            'pods' => [
              { 'name' => 'valid-1', 'cluster' => true, 'queues' => 'merge,post_receive' },
              { 'name' => 'valid-2', 'cluster' => false, 'negateQueues' => ['merge', 'post_receive'] }
            ]
          }
        }
      }.merge(default_required_values)
    end

    let(:error_values) do
      {
        'gitlab' => {
          'sidekiq' => {
            'pods' => [
              { 'name' => 'invalid-1', 'cluster' => true, 'queues' => ['merge'] },
              { 'name' => 'invalid-2', 'cluster' => true, 'negateQueues' => ['merge'] }
            ]
          }
        }
      }.merge(default_required_values)
    end

    let(:error_output) { '`queues` is not a string' }

    include_examples 'config validation',
                     success_description: 'when Sidekiq pods use cluster with string queues',
                     error_description: 'when Sidekiq pods use cluster with array queues'
  end

  describe 'sidekiq.queues.queueSelector' do
    # Simplify with https://gitlab.com/gitlab-com/gl-infra/scalability/-/issues/646
    ['queueSelector', 'experimentalQueueSelector'].each do |config|
      let(:success_values) do
        {
          'gitlab' => {
            'sidekiq' => {
              'pods' => [
                { 'name' => 'valid-1', 'cluster' => true, config => true },
              ]
            }
          }
        }.merge(default_required_values)
      end

      let(:error_values) do
        {
          'gitlab' => {
            'sidekiq' => {
              'pods' => [
                { 'name' => 'valid-1', 'cluster' => false, config => true },
              ]
            }
          }
        }.merge(default_required_values)
      end

      let(:error_output) { "`#{config}` only works when `cluster` is enabled" }

      include_examples 'config validation',
                       success_description: "when Sidekiq pods use #{config} with cluster enabled",
                       error_description: "when Sidekiq pods use #{config} without cluster enabled"
    end
  end

  describe 'database.externaLoadBalancing' do
    let(:success_values) do
      {
        'global' => {
          'psql' => {
            'host' => 'primary',
            'password' => { 'secret' => 'bar' },
            'load_balancing' => {
              'hosts' => [ 'a', 'b', 'c' ]
            }
          }
        },
        'postgresql' => { 'install' => false }
      }.merge(default_required_values)
    end

    let(:error_values) do
      {
        'global' => {
          'psql' => {
            'host' => 'primary',
            'password' => { 'secret' => 'bar' },
            'load_balancing' => {
              'hosts' => [ 'a', 'b', 'c' ]
            }
          }
        },
        'postgresql' => { 'install' => true }
      }.merge(default_required_values)
    end

    let(:error_output) { 'PostgreSQL is set to install, but database load balancing is also enabled' }

    include_examples 'config validation',
                     success_description: 'when database load balancing is configured, with PostgrSQL disabled',
                     error_description: 'when database load balancing is configured, with PostgrSQL enabled'

    describe 'database.externaLoadBalancing missing required elements' do
      let(:success_values) do
        {
          'global' => {
            'psql' => {
              'host' => 'primary',
              'password' => { 'secret' => 'bar' },
              'load_balancing' => {
                'hosts' => [ 'a', 'b', 'c' ]
              }
            }
          },
          'postgresql' => { 'install' => false }
        }.merge(default_required_values)
      end

      let(:error_values) do
        {
          'global' => {
            'psql' => {
              'host' => 'primary',
              'password' => { 'secret' => 'bar' },
              'load_balancing' => {
                'invalid' => 'item'
              }
            }
          },
          'postgresql' => { 'install' => false }
        }.merge(default_required_values)
      end

      let(:error_output) { 'You must specify `load_balancing.hosts` or `load_balancing.discover`' }

      include_examples 'config validation',
                      success_description: 'when database load balancing is configured per requirements',
                      error_description: 'when database load balancing is missing required elements'
    end

    describe 'database.externaLoadBalancing.hosts' do
      let(:success_values) do
        {
          'global' => {
            'psql' => {
              'host' => 'primary',
              'password' => { 'secret' => 'bar' },
              'load_balancing' => {
                'hosts' => [ 'a', 'b', 'c' ]
              }
            }
          },
          'postgresql' => { 'install' => false }
        }.merge(default_required_values)
      end

      let(:error_values) do
        {
          'global' => {
            'psql' => {
              'host' => 'primary',
              'password' => { 'secret' => 'bar' },
              'load_balancing' => {
                'hosts' => 'a'
              }
            }
          },
          'postgresql' => { 'install' => false }
        }.merge(default_required_values)
      end

      let(:error_output) { 'Database load balancing using `hosts` is configured, but does not appear to be a list' }

      include_examples 'config validation',
                      success_description: 'when database load balancing is configured for hosts, with an array',
                      error_description: 'when database load balancing is configured for hosts, without an array'
    end

    describe 'database.externaLoadBalancing.discover' do
      let(:success_values) do
        {
          'global' => {
            'psql' => {
              'host' => 'primary',
              'password' => { 'secret' => 'bar' },
              'load_balancing' => {
                'discover' => { 'record' => 'secondary' }
              }
            }
          },
          'postgresql' => { 'install' => false }
        }.merge(default_required_values)
      end

      let(:error_values) do
        {
          'global' => {
            'psql' => {
              'host' => 'primary',
              'password' => { 'secret' => 'bar' },
              'load_balancing' => {
                'discover' => true
              }
            }
          },
          'postgresql' => { 'install' => false }
        }.merge(default_required_values)
      end

      let(:error_output) { 'Database load balancing using `discover` is configured, but does not appear to be a map' }

      include_examples 'config validation',
                      success_description: 'when database load balancing is configured for discover, with a map',
                      error_description: 'when database load balancing is configured for discover, without a map'
    end
  end

  describe 'geo.database' do
    let(:success_values) do
      {
        'global' => {
          'geo' => { 'enabled' => true },
          'psql' => { 'host' => 'foo', 'password' => { 'secret' => 'bar' } }
        }
      }.merge(default_required_values)
    end

    let(:error_values) do
      {
        'global' => {
          'geo' => { 'enabled' => true }
        }
      }.merge(default_required_values)
    end

    let(:error_output) { 'Geo was configured but no database was provided' }

    include_examples 'config validation',
                     success_description: 'when Geo is enabled with a database',
                     error_description: 'when Geo is enabled without a database'
  end

  describe 'geo.secondary.database' do
    let(:success_values) do
      {
        'global' => {
          'geo' => { 'enabled' => true },
          'psql' => { 'host' => 'foo', 'password' => { 'secret' => 'bar' } }
        }
      }.merge(default_required_values)
    end

    let(:error_values) do
      {
        'global' => {
          'geo' => { 'enabled' => true, 'role' => 'secondary' },
          'psql' => { 'host' => 'foo', 'password' => { 'secret' => 'bar' } }
        }
      }.merge(default_required_values)
    end

    let(:error_output) { 'Geo was configured with `role: secondary`, but no database was provided' }

    include_examples 'config validation',
                     success_description: 'when Geo is enabled with a database',
                     error_description: 'when Geo is enabled without a database'
  end

  describe 'appConfig.maxRequestDurationSeconds' do
    let(:success_values) do
      {
        'global' => {
          'appConfig' => { 'maxRequestDurationSeconds' => 50 },
          'webservice' => { 'workerTimeout' => 60 }
        }
      }.merge(default_required_values)
    end

    let(:error_values) do
      {
        'global' => {
          'appConfig' => { 'maxRequestDurationSeconds' => 70 },
          'webservice' => { 'workerTimeout' => 60 }
        }
      }.merge(default_required_values)
    end

    let(:error_output) { 'global.appConfig.maxRequestDurationSeconds (70) is greater than or equal to global.webservice.workerTimeout (60)' }

    include_examples 'config validation',
                     success_description: 'when maxRequestDurationSeconds is less than workerTimeout',
                     error_description: 'when maxRequestDurationSeconds is greater than or equal to workerTimeout'
  end

  describe 'appConfig.sentry.dsn' do
    let(:success_values) do
      {
        'registry' => {
          'reporting' => {
            'sentry' => {
              'enabled' => true,
              'dsn' => 'somedsn'
            }
          }
        }
      }.merge(default_required_values)
    end

    let(:error_values) do
      {
        'registry' => {
          'reporting' => {
            'sentry' => {
              'enabled' => true
            }
          }
        }
      }.merge(default_required_values)
    end

    let(:error_output) { 'When enabling sentry, you must configure at least one DSN.' }

    include_examples 'config validation',
                     success_description: 'when Sentry is enabled and DSN is defined',
                     error_description: 'when Sentry is enabled but DSN is undefined'
  end

  describe 'gitaly.extern.repos' do
    let(:success_values) do
      {
        'global' => {
          'gitaly' => { 'enabled' => false, 'external' => [{ 'name' => 'foo', 'hostname' => 'bar' }] }
        }
      }.merge(default_required_values)
    end

    let(:error_values) do
      {
        'global' => {
          'gitaly' => { 'enabled' => false, 'external' => [] }
        }
      }.merge(default_required_values)
    end

    let(:error_output) { 'external Gitaly repos needs to be specified if global.gitaly.enabled is not set' }

    include_examples 'config validation',
                     success_description: 'when Gitaly is disabled and external repos are enabled',
                     error_description: 'when Gitaly and external repos are disabled'
  end

  describe 'gitaly.task-runner.replicas' do
    let(:success_values) do
      {
        'gitlab' => {
          'task-runner' => { 'replicas' => 1, 'persistence' => { 'enabled' => true } }
        }
      }.merge(default_required_values)
    end

    let(:error_values) do
      {
        'gitlab' => {
          'task-runner' => { 'replicas' => 2, 'persistence' => { 'enabled' => true } }
        }
      }.merge(default_required_values)
    end

    let(:error_output) { 'more than 1 replica, but also with a PersistentVolumeClaim' }

    include_examples 'config validation',
                     success_description: 'when task-runner has persistence enabled and one replica',
                     error_description: 'when task-runner has persistence enabled and more than one replica'
  end

  describe 'multipleRedis' do
    let(:success_values) do
      {
        'redis' => { 'install' => true }
      }.merge(default_required_values)
    end

    let(:error_values) do
      {
        'redis' => { 'install' => true },
        'global' => {
          'redis' => { 'cache' => { 'host' => 'foo' } }
        }
      }.merge(default_required_values)
    end

    let(:error_output) { 'If configuring multiple Redis servers, you can not use the in-chart Redis server' }

    include_examples 'config validation',
                     success_description: 'when Redis is set to install with a single Redis instance',
                     error_description: 'when Redis is set to install with multiple Redis instances'
  end

  describe 'dependencyProxy.puma' do
    let(:success_values) do
      {
        'global' => {
          'appConfig' => {
            'dependencyProxy' => { 'enabled' => true }
          }
        }
      }.merge(default_required_values)
    end

    let(:error_values) do
      {
        'global' => {
          'appConfig' => {
            'dependencyProxy' => { 'enabled' => true }
          }
        },
        'gitlab' => {
          'webservice' => { 'webServer' => 'unicorn' }
        }
      }.merge(default_required_values)
    end

    let(:error_output) { 'You must be using the Puma webservice in order to use Dependency Proxy.' }

    include_examples 'config validation',
                     success_description: 'when dependencyProxy is enabled with a default install',
                     error_description: 'when dependencyProxy is enabled with the unicorn webservice'
  end

  describe 'webserviceTermination' do
    let(:success_values) do
      {
        'gitlab' => {
          'webservice' => {
            'deployment' => {
              'terminationGracePeriodSeconds' => 50
            },
            'shutdown' => {
              'blackoutSeconds' => 10
            }
          }
        }
      }.merge(default_required_values)
    end

    let(:error_values) do
      {
        'gitlab' => {
          'webservice' => {
            'deployment' => {
              'terminationGracePeriodSeconds' => 5
            },
            'shutdown' => {
              'blackoutSeconds' => 20
            }
          }
        }
      }.merge(default_required_values)
    end

    let(:error_output) { 'fail' }

    include_examples 'config validation',
                     success_description: 'when terminationGracePeriodSeconds is >= blackoutSeconds',
                     error_description: 'when terminationGracePeriodSeconds is < blackoutSeconds'
  end

  describe 'registry.database (PG version)' do
    let(:success_values) do
      YAML.safe_load(%(
        postgresql:
          image:
            tag: 12

        global:
          registry:
            database:
              enabled: true
      )).merge(default_required_values)
    end

    let(:error_values) do
      YAML.safe_load(%(
        postgresql:
          image:
            tag: 11

        global:
          registry:
            database:
              enabled: true
      )).merge(default_required_values)
    end

    let(:error_output) { 'PostgreSQL 12 is the minimum required version' }

    include_examples 'config validation',
                     success_description: 'when postgresql.image.tag is >= 12',
                     error_description: 'when postgresql.image.tag is < 12'
  end

  describe 'registry.database (sslmode)' do
    let(:success_values) do
      YAML.safe_load(%(
        postgresql:
          image:
            tag: 12

        global:
          registry:
            database:
              enabled: true
              sslmode: disable
      )).merge(default_required_values)
    end

    let(:error_values) do
      YAML.safe_load(%(
        postgresql:
          image:
            tag: 12

        global:
          registry:
            database:
              enabled: true
              sslmode: testing
      )).merge(default_required_values)
    end

    let(:error_output) { 'Invalid SSL mode' }

    include_examples 'config validation',
                     success_description: 'when database.sslmode is valid',
                     error_description: 'when when database.sslmode is not valid'
  end

  describe 'registry.migration (disablemirrorfs)' do
    let(:success_values) do
      YAML.safe_load(%(
        postgresql:
          image:
            tag: 12

        registry:
          database:
            enabled: true
          migration:
            disablemirrorfs: true
      )).merge(default_required_values)
    end

    let(:error_values) do
      YAML.safe_load(%(
        postgresql:
          image:
            tag: 12

        registry:
          migration:
            disablemirrorfs: true
      )).merge(default_required_values)
    end

    let(:error_output) { 'Disabling filesystem metadata requires the metadata database to be enabled' }

    include_examples 'config validation',
                     success_description: 'when migration disablemirrorfs is true, with database enabled',
                     error_description: 'when migration disablemirrorfs is true, with database disabled'
  end
end
