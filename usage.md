# Usage

Working with All Futures is very similar to working with a Rails model class. Depending on what you want to build, you will define the attributes, validations, callbacks and instance methods you need.

## Creating a faceted search filter

Define a class that inherits from `AllFutures`, in a location that makes sense for your application. Many times, `app/models` is a suitable home but in the example, an `app/filters` folder was created.

Your first task is to define attributes representing the data structure you intend to persist. `attribute` supports all of the same data types you could use in a migration:

{% code title="app/filters/customer\_filter.rb" %}
```ruby
class CustomerFilter < AllFutures
  # Facets
  attribute :search, :string
  attribute :threshold, :float, default: 0.1
  attribute :status, :string
  attribute :lawyers, :boolean, default: false
  attribute :low, :integer, default: 21
  attribute :high, :integer, default: 65
  
  # Pagination
  attribute :items, :integer, default: 10
  attribute :page, :integer, default: 1
  
  # Sorting
  attribute :order, :string, default: "name"
  attribute :direction, :string, default: "asc"
end
```
{% endcode %}

The above code is an example of using All Futures to implement an exclusion filter. It's taken from the [Beast Mode repo](https://github.com/leastbad/beast_mode), and is used to hold the values required to create a faceted search UI for a tabular dataset.

### Facets, Pagination and Sorting

When working with tabular data, there are typically three concerns:

1. **Facets**: attributes used to exclude and filter data from the total pool of possible values
2. **Pagination**: attributes used to track the current page and number of items per page
3. **Sorting**: attributes used to sort the filtered results in a specific direction \(ASC vs DESC\)

The `CustomerFilter` doesn't describe the data - that's the model's job. Instead, facets describe the ways a user might exclude rows. Facets are composable, meaning that you can add them together to remove more data. Ultimately, the filter that is applied is the sum total of all active facets.

![Hole In The Wall](.gitbook/assets/hole.jpg)

For example, the `lawyers` attribute is used to reduce the results to only rows where the name of the employer has the string `and` in it. `threshold` is used to alternate between loose and strict text matching. You can [see this for yourself](https://beastmode.leastbad.com/) if you search for "ste"; you'll see 7 results, unless you turn on _Uptight_ _mode_, which reduces the results to 3.

{% hint style="success" %}
When designing faceted search UIs, it's important that you handle impossible states so that there are no combinations of filters which could produce invalid combinations or even errors.

For example, it's recommended that you configure Pagy so that a user viewing page 10 is automatically taken to page 5 if the user adjust the number of records per-page from 10 to 20. Set `Pagy::VARS[:overflow] = :last_page` in your `pagy.rb` initializer.
{% endhint %}

### Providing a scope

Since this example doesn't require any attribute validation, we complete the Filter by defining a `scope` method to return an `ActiveRecord::Relation` object. You can pass this relation directly into Pagy to perform the search, or additional scope clauses can be added to suit the needs of your application.

```ruby
class CustomerFilter < AllFutures

  # Attribute definitions cut for brevity

  def scope
    Customer
      .with_status(status)
      .only_lawyers(lawyers)
      .between(low, high)
      .order(order => direction)
      .search_for(search, threshold)
  end
  
end
```

The business logic required to filter the data is fully contained in the model as a set of scopes. This `CustomerFilter#scope` method simply connects the dots to provide access to a relation for _this_ filter instance.

