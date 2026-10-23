#pragma once

#include "settings/objectnode.hpp"
#include "common.hpp"

#include <qstringlist.h>

namespace caelestia::shell::config {

class DockConfig : public settings::ObjectNode {
    CONFIG_NODE(DockConfig, settings::ObjectNode)

    CONFIG_PROPERTY(bool, enabled, true)
    CONFIG_PROPERTY(bool, showOnHover, true)
    CONFIG_PROPERTY(int, maxSlots, 5)
    CONFIG_PROPERTY(int, dragThreshold, 50)
    CONFIG_GLOBAL_PROPERTY(QStringList, pinnedApps, {})
};

} // namespace caelestia::shell::config
