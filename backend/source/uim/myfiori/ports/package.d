/// Ports: the interfaces between the application core and its adapters.
///  - driving (inbound): usecases, services
///  - driven (outbound): repositories, storages, gateways, messaging
module uim.myfiori.ports;

public import uim.myfiori.ports.repositories;
public import uim.myfiori.ports.storages;
public import uim.myfiori.ports.services;
public import uim.myfiori.ports.gateways;
public import uim.myfiori.ports.messaging;
public import uim.myfiori.ports.usecases;
