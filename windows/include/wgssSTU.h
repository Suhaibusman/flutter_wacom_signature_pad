#pragma once

// Shim for missing wgssSTU.h in newer SDKs
// Maps old wgssSTU namespace to WacomGSS::STU

#include <WacomGSS/STU/Tablet.hpp>
#include <WacomGSS/STU/Protocol.hpp>
#include <WacomGSS/STU/Interface.hpp>
#include <WacomGSS/STU/InterfaceQueue.hpp>
#include <WacomGSS/STU/ReportHandler.hpp>

// Namespace alias
namespace wgssSTU = WacomGSS::STU;
