# Copyright (C) 2018-2019 MongoDB, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

module Mongo
  class Error

    # Raised when authentication fails.
    #
    # Note: This class is derived from RuntimeError for
    # backwards compatibility reasons. It is subject to
    # change in future major versions of the driver.
    #
    # @since 2.10.1
    class AuthError < RuntimeError
      include Notable
    end
  end
end
