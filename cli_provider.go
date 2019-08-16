package katyusha

import (
	"net"
)

type CliProvider struct {
	Name string
}

func (p *CliProvider) GetHosts(name string) Hosts {
	if _, err := net.LookupHost(name); err != nil {
		return Hosts{}
	}
	return Hosts{NewHost(name, HostAttributes{})}

}
