import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/service_catalog/domain/service_detail.dart';
import 'package:ai_clinic/features/service_catalog/domain/service_list_item.dart';
import 'package:flutter/foundation.dart';

/// Mutable service form draft (web `ServiceFormValues`).
@immutable
class ServiceFormValues {
  const ServiceFormValues({this.name = '', this.price});

  final String name;
  final double? price;

  ServiceFormValues copyWith({String? name, double? price, bool clearPrice = false}) {
    return ServiceFormValues(name: name ?? this.name, price: clearPrice ? null : (price ?? this.price));
  }

  ServiceFormValues applyPatch({String? name, double? price, bool clearPrice = false}) {
    return copyWith(name: name, price: price, clearPrice: clearPrice);
  }
}

typedef ServiceFormErrors = Map<String, String>;

ServiceFormValues emptyServiceFormValues() => const ServiceFormValues();

ServiceFormValues serviceListItemToFormValues(ServiceListItem service) {
  return ServiceFormValues(
    name: service.name,
    price: service.defaultPrice.isZero ? null : service.defaultPrice.asDouble,
  );
}

ServiceFormValues serviceDetailToFormValues(ServiceDetail detail) {
  return ServiceFormValues(
    name: detail.service.name,
    price: detail.service.defaultPrice.isZero ? null : detail.service.defaultPrice.asDouble,
  );
}

String priceToWire(double price) => Money.parse(price.toStringAsFixed(2)).wireValue;

ServiceFormErrors validateServiceFormValues(ServiceFormValues values) {
  final errors = <String, String>{};

  if (values.name.trim().isEmpty) {
    errors['name'] = 'Service name is required';
  }

  if (values.price == null) {
    errors['price'] = 'Default price is required';
  } else if (values.price! < 0) {
    errors['price'] = 'Price must be zero or greater';
  }

  return errors;
}
