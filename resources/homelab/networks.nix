{
  vlans = {
    mgmt = {
      id = 30;
      cidr = "10.3.30.0/24";
      gateway = "10.3.30.1";
      dnsDomain = "lab.h4xx.io";
    }; # untagged on servers
    storage = {
      id = 40;
      cidr = "10.3.40.0/24";
      gateway = "10.3.40.1";
      dhcp = true;
    };
    server = {
      id = 20;
      cidr = "10.3.20.0/24";
      gateway = "10.3.20.1";
      dhcp = true;
    };
    lan = {
      id = 10;
      cidr = "10.3.10.0/24";
      gateway = "10.3.10.1";
    };
    iot = {
      id = 12;
      cidr = "10.3.12.0/24";
      gateway = "10.3.12.1";
    };
    windows = {
      id = 13;
      cidr = "10.3.13.0/24";
      gateway = "10.3.13.1";
    };
    lab = {
      id = 50;
      cidr = "10.3.50.0/24";
      gateway = "10.3.50.1";
    };
  };
}
