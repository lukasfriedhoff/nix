{
  vlans = {
    mgmt = {
      id = 30;
      cidr = "10.1.30.0/24";
      dnsDomain = "lab.h4xx.io";
    }; # untagged on servers
    storage = {
      id = 40;
      cidr = "10.1.40.0/24";
      dhcp = true;
    };
    server = {
      id = 20;
      cidr = "10.1.20.0/24";
      dhcp = true;
    };
    lan = {
      id = 10;
      cidr = "10.1.10.0/24";
    };
    iot = {
      id = 12;
      cidr = "10.1.12.0/24";
    };
    windows = {
      id = 13;
      cidr = "10.1.13.0/24";
    };
    lab = {
      id = 50;
      cidr = "10.1.50.0/24";
    };
  };
}
