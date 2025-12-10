Ansible deploy za monitoring stack:

- inventory/hosts.ini : definiši hostove
- install-stack.yml   : deploy compose stack
- install-services.yml: deploy systemd servise (compose service, exporter service+timer)
- main.yml    : import stack + services

Deoloy:

- ansible-playbook -i inventory/hosts.ini monitoring.yml --tags stack -u <account> --ask-become-pass
- ansible-playbook -i inventory/hosts.ini monitoring.yml --tags services -u <account> --ask-become-pass
- ansible-playbook -i inventory/hosts.ini monitoring.yml --tags stack,service -u <account> --ask-become-pass

 + Templates su u templates/, skripta u files/.
 + Scripte za rucno pokretanje lustre reportinga i setovanja soft-quote su scripts folderu
 + Script za prikupljanje metrica lustre_exporter.sh upisuje u exporter podfolder stacka,u lustre.prom file.
 + Ako je potrebno ad-hoc dobijanje trenutnog listinga lustre zauzeca moze se pokrenuti i rucno pod root nalogom.
 + Prometheus storage mapped na /root/lustre-exporter/prometheus
 + Grafana je na portu 3500 (host).
 + Prometheus retention postavljen na 9h u compose command args.
