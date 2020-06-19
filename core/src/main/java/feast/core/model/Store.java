/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright 2018-2019 The Feast Authors
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
package feast.core.model;

import static feast.common.function.Store.parseSubscriptionFrom;

import com.google.protobuf.InvalidProtocolBufferException;
import feast.proto.core.StoreProto;
import feast.proto.core.StoreProto.Store.BigQueryConfig;
import feast.proto.core.StoreProto.Store.Builder;
import feast.proto.core.StoreProto.Store.CassandraConfig;
import feast.proto.core.StoreProto.Store.RedisClusterConfig;
import feast.proto.core.StoreProto.Store.RedisConfig;
import feast.proto.core.StoreProto.Store.StoreType;
import feast.proto.core.StoreProto.Store.Subscription;
import java.util.ArrayList;
import java.util.List;
import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.Id;
import javax.persistence.Lob;
import javax.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.Setter;

@Getter
@Setter
@AllArgsConstructor
@Entity
@Table(name = "stores")
public class Store {

  // Name of the store. Must be unique
  @Id
  @Column(name = "name", nullable = false, unique = true)
  private String name;

  // Type of the store, should map to feast.core.Store.StoreType
  @Column(name = "type", nullable = false)
  private String type;

  // Connection string to the database
  @Column(name = "config", nullable = false)
  @Lob
  private byte[] config;

  // FeatureSets this store is subscribed to, comma delimited.
  @Column(name = "subscriptions")
  private String subscriptions;

  public Store() {
    super();
  }

  public static Store fromProto(StoreProto.Store storeProto) throws IllegalArgumentException {
    List<String> subs = new ArrayList<>();
    for (Subscription s : storeProto.getSubscriptionsList()) {
      subs.add(parseSubscriptionFrom(s));
    }
    byte[] config;
    switch (storeProto.getType()) {
      case REDIS:
        config = storeProto.getRedisConfig().toByteArray();
        break;
      case BIGQUERY:
        config = storeProto.getBigqueryConfig().toByteArray();
        break;
      case CASSANDRA:
        config = storeProto.getCassandraConfig().toByteArray();
        break;
      case REDIS_CLUSTER:
        config = storeProto.getRedisClusterConfig().toByteArray();
        break;
      default:
        throw new IllegalArgumentException("Invalid store provided");
    }
    return new Store(
        storeProto.getName(), storeProto.getType().toString(), config, String.join(",", subs));
  }

  public StoreProto.Store toProto() throws InvalidProtocolBufferException {
    List<Subscription> subscriptionProtos = getSubscriptionsByStr(false);
    Builder storeProtoBuilder =
        StoreProto.Store.newBuilder()
            .setName(name)
            .setType(StoreType.valueOf(type))
            .addAllSubscriptions(subscriptionProtos);
    switch (StoreType.valueOf(type)) {
      case REDIS:
        RedisConfig redisConfig = RedisConfig.parseFrom(config);
        return storeProtoBuilder.setRedisConfig(redisConfig).build();
      case BIGQUERY:
        BigQueryConfig bqConfig = BigQueryConfig.parseFrom(config);
        return storeProtoBuilder.setBigqueryConfig(bqConfig).build();
      case CASSANDRA:
        CassandraConfig cassConfig = CassandraConfig.parseFrom(config);
        return storeProtoBuilder.setCassandraConfig(cassConfig).build();
      case REDIS_CLUSTER:
        RedisClusterConfig redisClusterConfig = RedisClusterConfig.parseFrom(config);
        return storeProtoBuilder.setRedisClusterConfig(redisClusterConfig).build();
      default:
        throw new InvalidProtocolBufferException("Invalid store set");
    }
  }

  /**
   * Returns a List of Subscriptions based on whether to include those with excluded flag.
   * Currently, store's subscriptions string will store ALL subscriptions, but during retrieval for
   * subscriptions, the exclude flag provided by this function will be used for filtering.
   *
   * @param exclude boolean flag to signify whether to return subscriptions which have excluded flag
   * @return List of Subscription that based on exclusion filter
   */
  public List<Subscription> getSubscriptionsByStr(boolean exclude) {
    List<Subscription> subscriptions = parseSubscriptionFrom(this.getSubscriptions(), exclude);

    return subscriptions;
  }
}
