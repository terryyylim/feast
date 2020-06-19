/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright 2018-2020 The Feast Authors
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package feast.common.function;

import feast.proto.core.FeatureSetProto;
import feast.proto.core.FeatureSetReferenceProto;

public class FeatureSet {

  /**
   * Accepts FeatureSetSpec object and returns its reference in String "project/featureset_name".
   *
   * @param featureSetSpec
   * @return String format of FeatureSetReference
   */
  public static String getFeatureSetStringRef(FeatureSetProto.FeatureSetSpec featureSetSpec) {
    return String.format("%s/%s", featureSetSpec.getProject(), featureSetSpec.getName());
  }

  /**
   * Accepts FeatureSetReference object and returns its reference in String
   * "project/featureset_name".
   *
   * @param featureSetReference
   * @return String format of FeatureSetReference
   */
  public static String getFeatureSetStringRef(
      FeatureSetReferenceProto.FeatureSetReference featureSetReference) {
    return String.format("%s/%s", featureSetReference.getProject(), featureSetReference.getName());
  }
}
