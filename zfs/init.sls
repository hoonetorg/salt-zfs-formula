{% from "zfs/map.jinja" import zfs with context %}

zfs__cmd_requirements_are_installed:
  cmd.run:
    - name: echo "requirements are installed"
    - unless: /bin/true
{% set slsrequires =salt['pillar.get']('zfs:slsrequires', False) %}
{% if slsrequires is defined and slsrequires %}
    - require:
{% for slsrequire in slsrequires %}
      - {{slsrequire}}
{% endfor %}
{% endif %}

{% set zfs_data = salt['pillar.get']('zfs:data', {}) %}

{% if zfs_data.module_opts is defined and zfs_data.module_opts %}
zfs__file_/etc/modprobe.d/zfs.conf:
  file.managed:
    - name: /etc/modprobe.d/zfs.conf
    - require:
      - cmd: zfs__cmd_requirements_are_installed
    - watch_in:
      - cmd: zfs__cmd_dracut
    - require_in:
      - pkg: zfs__pkg_zfs
    - contents: |
{% for zfs_module_opt in zfs_data.module_opts|sort %}
        {{zfs_module_opt}}
{% endfor %}
{% endif %}

{% if zfs_data.kernel_opts is defined and zfs_data.kernel_opts %}
zfs__file_/etc/sysctl.d/zfs.conf:
  file.managed:
    - name: /etc/sysctl.d/zfs.conf
    - require:
      - cmd: zfs__cmd_requirements_are_installed
    - watch_in:
      - cmd: zfs__cmd_dracut
    - contents: |
{% for zfs_kernel_key,zfs_kernel_value in zfs_data.kernel_opts.items()|sort %}
        {{zfs_kernel_key}} = {{zfs_kernel_value}}
{% endfor %}

zfs__cmd_sysctl_restart:
  cmd.wait:
    - name: systemctl restart systemd-sysctl
    - require:
      - cmd: zfs__cmd_requirements_are_installed
    - watch_in:
      - cmd: zfs__cmd_dracut
    - require_in:
      - pkg: zfs__pkg_zfs
    - watch:
      - file: zfs__file_/etc/sysctl.d/zfs.conf
{% endif %}

zfs__cmd_dracut:
  cmd.wait:
    - name: dracut -f
    - require:
      - cmd: zfs__cmd_requirements_are_installed
    - require_in:
      - pkg: zfs__pkg_zfs

zfs__pkg_zfs:
  pkg.installed:
    - pkgs:
      #- kernel-devel
      - zfs
    - require:
      - cmd: zfs__cmd_requirements_are_installed

zfs__modprobe_zfs:
  cmd.run:
    - name: modprobe zfs
    - unless: lsmod|grep zfs
    - require:
      - pkg: zfs__pkg_zfs

{% for service, service_data in zfs.services.items()|sort %}
zfs__services_{{service}}:
  service.{{service_data.state}}:
    - name: {{service}}
{% if service_data.get('enabled', False) %}
    - enable: True
{% endif %}
    - require:
      - cmd: zfs__modprobe_zfs
    - require_in:
      - cmd: zfs__install_finished
{% endfor %}

zfs__install_finished:
  cmd.run:
    - name: /bin/true
    - unless: /bin/true

{% for pool, pool_data in zfs_data.pools.items()|sort %}

zfs__pool_create_{{pool}}:
  cmd.run:
    - name: zpool create {{pool_data.create_opts}} {{pool}} {{pool_data.vdevs}}
    - unless: zpool list {{pool}} || zpool import -f {{pool}}
    - onlyif: test -z "`blkid -c /dev/null $(echo '{{pool_data.vdevs}}'|perl -pe 's/\b(log|cache|spare|mirror|raidz[1-3]*)\b//g') |grep zfs_member`"
    - require:
      - cmd: zfs__install_finished

zfs__pool_import_{{pool}}:
  cmd.run:
    - name: zpool import -f {{pool}}
    - unless: zpool list {{pool}} 
    - require:
      - cmd: zfs__pool_create_{{pool}}


{% if pool_data.opts is defined and pool_data.opts %}
{% for poolopt, poolopt_data in pool_data.opts.items()|sort %}
zfs__poolopts_{{pool}}_{{poolopt}}:
  cmd.run:
    - name: zpool set {{poolopt}}={{poolopt_data}} {{pool}}
    - unless: test "`zpool get -H -p {{poolopt}} {{pool}}|awk '{print $3}'`" == "{{poolopt_data}}"
    - require:
      - cmd: zfs__pool_import_{{pool}}
{% endfor %}
{% endif %}

{% if pool_data.volumeopts is defined and pool_data.volumeopts %}
{% for volumeopt, volumeopt_data in pool_data.volumeopts.items()|sort %}
zfs__poolvolumeopts_{{pool}}_{{volumeopt}}:
  cmd.run:
    - name: zfs set {{volumeopt}}={{volumeopt_data}} {{pool}}
    - unless: test "`zfs get -H -p -o value {{volumeopt}} {{pool}}`" == "{{volumeopt_data}}"
    - require:
      - cmd: zfs__pool_import_{{pool}}
{% endfor %}
{% endif %}

{% if pool_data.volumes is defined and pool_data.volumes %}
{% for volume, volume_data in pool_data.volumes.items()|sort %}
zfs__create_volume_{{pool}}_{{volume}}:
  cmd.run:
    - name: zfs create {{volume_data.create_opts}} {{pool}}/{{volume}}
    - unless: zfs list {{pool}}/{{volume}}
    - require:
      - cmd: zfs__pool_import_{{pool}}

{% if volume_data.opts is defined and volume_data.opts %}
{% for volumeopt, volumeopt_data in volume_data.opts.items()|sort %}
zfs__volumeopts_{{pool}}/{{volume}}_{{volumeopt}}:
  cmd.run:
    - name: zfs set {{volumeopt}}={{volumeopt_data}} {{pool}}/{{volume}}
    - unless: test "`zfs get -H -p -o value {{volumeopt}} {{pool}}/{{volume}}`" == "{{volumeopt_data}}"
    - require:
      - cmd: zfs__pool_import_{{pool}}
{% endfor %}
{% endif %}

{% endfor %}
{% endif %}

{% endfor %}
