// Copyright (c) 2026 Aaron Bamblett
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

/// `main()` entry time. Set on the first line of `main()` and read by the
/// library screen for the `startup_ms` report.
DateTime? appMainEntry;

/// Set once the first grid frame with data has reported its startup time.
bool startupReported = false;
