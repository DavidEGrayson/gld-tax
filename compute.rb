require 'bigdecimal'
require 'date'

class DataError < StandardError

end

class Transaction
  Types = [:buy, :sell]

  attr_reader :date
  attr_reader :type
  attr_reader :quantity
  attr_reader :unit_price

  def initialize(date, type, quantity, unit_price)
    @date = date
    @type = type
    @quantity = quantity
    @unit_price = unit_price
  end

  def extended_price
    quantity * unit_price
  end
end

def parse_transactions(csv)
  last_date = nil
  csv.each_line.map do |line|
    data = line.split(',')
    if data.size != 4
      raise DataError, "wrong number of entries on transaction line: #{line}"
    end

    date = Date.parse(data[0])
    if last_date && last_date > date
      raise DataError, "dates out of order in transaction file, starting at #{date}"
    end

    type = data[1].to_sym
    if !Transaction::Types.include?(type)
      raise DataError, "invalid transaction type #{type}"
    end

    quantity = BigDecimal(data[2])
    if quantity <= 0
      raise DataError, "non-positive share quantity #{quantity}"
    end

    unit_price = BigDecimal(data[3])
    if unit_price <= 0
      raise DataError, "non-positive price per share #{price_per_share}"
    end

    Transaction.new(date, type, quantity, unit_price)
  end
end

class Lot
  attr_accessor :quantity
  attr_accessor :buy_transaction
  attr_accessor :sell_transaction

  def initialize(quantity, buy_transaction, sell_transaction = nil)
    @quantity = quantity
    @buy_transaction = buy_transaction
    @sell_transaction = sell_transaction
  end

  def sell_date
    sell_transaction.date if sell_transaction
  end

  def sell_price
    sell_transaction.price if sell_transaction
  end

  def buy_date
    buy_transaction.date
  end

  def buy_price
    buy_transaction.extended_price
  end
end

def break_into_lots(transactions)
  # Decompose buy/sell transactions into a series of lots using
  # FIFO.

  unsold_buys = []
  lots = []

  transactions.each do |tx|
    case tx.type
    when :buy
      buy = { transaction: tx, quantity: tx.quantity }
      unsold_buys << buy
    when :sell
      quantity = tx.quantity
      while quantity > 0
        # Each iteration of this loop generates another lot until the
        # sell transaction is totally represented as lots.

        buy = unsold_buys.first

        if !buy
          raise DataError, "unmatchable sell on #{tx.date}"
        end

        # Figure out the quantity of this lot.
        lot_quantity = [buy[:quantity], quantity].min

        # Subtract that quantity from the unmatched buys.
        buy[:quantity] -= lot_quantity
        unsold_buys.shift if buy[:quantity].zero?

        # Subtract that quantity from the unmatched sell quantity.
        quantity -= lot_quantity

        # Record the lot.
        lots << Lot.new(lot_quantity, buy[:transaction], tx)
      end
    else
      raise "Unrecognized transaction type: #{tx.type}"
    end
  end

  lots += unsold_buys.map do |buy|
    Lot.new(buy[:quantity], buy[:transaction])
  end

  lots
end

class ProceedRecord
  attr_reader :date
  attr_reader :gold_ounces        # gold ounces per share
  attr_reader :gold_ounces_sold   # to cover expenses
  attr_reader :proceeds           # dollars per share

  def initialize(date, gold_ounces, gold_ounces_sold, proceeds)
    @date = date
    @gold_ounces = gold_ounces
    @gold_ounces_sold = gold_ounces_sold
    @proceeds = proceeds
  end
end

def parse_proceeds(csv)
  last_date = nil
  csv.each_line.map do | line|
    data = line.split(',')

    if ![2, 4].include?(data.size)
      raise DataError, "wrong number of entries on line: #{line}"
    end

    date = Date.parse(data[0])
    if last_date && date != last_date + 1
      raise DataError, "unexpected proceeds date: #{last_date} followed by #{date}"
    end

    gold_ounces = BigDecimal(data[1])
    if gold_ounces <= 0
      raise DataError, "non-positive gold ounces per share #{gold_ounces}"
    end

    gold_ounces_sold = 0
    proceeds = 0

    if data.size == 4
      gold_ounces_sold = BigDecimal(data[2])
      proceeds = BigDecimal(data[3])
    end

    ProceedRecord.new(date, gold_ounces, gold_ounces_sold, proceeds)
  end
end

def check_lots(lots, transactions)
  # Basic sanity checks for lots.
  lots.each do |lot|
    if !lot.quantity.is_a?(BigDecimal)
      raise "invalid quantity class: #{lot.quantity.class}"
    end

    if !lot.buy_transaction.is_a?(Transaction)
      raise "invalid buy_transaction: #{lot.buy_transaction.inspect}"
    end

    if lot.sell_date && lot.sell_date < lot.buy_date
      raise "lot sold before it was bought: #{lot.inspect}"
    end
  end

  # Make sure the lots use a FIFO.
  lots.each_cons(2) do |lot1, lot2|
    if !(lot1.buy_date <= lot2.buy_date)
      raise 'lots buy dates out of order'
    end

    if lot1.sell_date
      # lot1 was sold, so expect lot2 to be unsold or sold at a
      # later date.
      if lot2.sell_date && !(lot1.sell_date <= lot2.sell_date)
        raise 'lot sell dates out of order'
      end
    else
      # lot1 was not sold, so expect lot2 to not be sold
      if lot2.sell_date
        raise 'a sold lot appears after an unsold one'
      end
    end
  end

  # Make sure each transaction is represented by some number of lots
  # and the quantities of those lots add up to the quantity of the
  # transaction.
  mapping = {sell: :sell_transaction, buy: :buy_transaction}
  transactions.each do |tx|
    lot_field = mapping[tx.type]
    lots_for_transaction = lots.select do |lot|
      lot.send(lot_field) == tx
    end

    lot_quantity = lots_for_transaction.reduce(0) do |total, lot|
      total + lot.quantity
    end

    if lot_quantity != tx.quantity
      raise "lot quantities do not add up to transaction quantity: " \
        "expected #{tx.quantity}, got #{lot_quantity}"
    end
  end
end

def print_lots(lots)
  puts "Lots: "
  puts "%12s  %-10s  %-10s" % ['quantity', 'buy date', 'sell date' ]
  lots.each do |lot|
    puts "%12.4f  %-10s  %-10s" % [lot.quantity, lot.buy_date, lot.sell_date || '-']
  end
  puts
end

def find_proceed_for_date(proceeds, date)
  proceeds.find do |proceed|
    proceed.date == date
  end
end

def find_proceeds_for_date_range(proceeds, date_range)
  proceeds.select do |proceed|
    date_range === proceed.date
  end
end

class CapitalChange
  attr_reader :buy_price
  attr_reader :sell_price
  attr_reader :buy_date
  attr_reader :sell_date
  attr_reader :source

  def initialize(buy_price, sell_price, buy_date, sell_date, source = nil)
    @buy_price = buy_price
    @sell_price = sell_price
    @buy_date = buy_date
    @sell_date = sell_date
    @source = source
  end

  def amount
    sell_price - buy_price
  end

  def gain?
    amount > 0
  end

  def loss?
    amount < 0
  end

  def short_term?
    (sell_date - buy_date).to_i < 365
  end

  def long_term?
    !short_term?
  end

  def cost
    buy_price
  end

  def proceeds
    sell_price
  end
end

def calculate_gold_sales(lots, proceeds)
  changes = []

  lots.each do |lot|
    # Figure out how much gold was bought in this lot (step 1 from GLD PDF).
    proceed = find_proceed_for_date(proceeds, lot.buy_date)
    gold_ounces = proceed.gold_ounces * lot.quantity

    cost_per_ounce = lot.buy_price / gold_ounces

    adjusted_cost_basis = lot.buy_price

    if lot.sell_date
      date_range = (lot.buy_date + 1)..(lot.sell_date - 1)
    else
      date_range = (lot.buy_date + 1)..Date::Infinity.new
    end
    lot_proceeds = find_proceeds_for_date_range(proceeds, date_range)

    lot_proceeds.each do |proceed|
      if proceed.gold_ounces_sold > 0
        # Some gold was sold.

        # Calculate how much gold was sold (step 2 from GLD PDF).
        gold_ounces_sold = proceed.gold_ounces_sold * lot.quantity

        # Calculate cost of gold sold (step 3 from GLD PDF).
        cost_of_gold_sold = gold_ounces_sold * cost_per_ounce

        # Calculate proceeds from gold sold.
        proceeds_of_gold_sold = lot.quantity * proceed.proceeds

        # Calcualte shareholder's gain or loss (step 4 from GLD PDF).
        gain = proceeds_of_gold_sold - cost_of_gold_sold

        changes << CapitalChange.new(cost_of_gold_sold, proceeds_of_gold_sold,
                                     lot.buy_date, proceed.date, lot)

        # Calcualte the adjusted cost basis (step 6 from GLD PDF)
        adjusted_cost_basis -= cost_of_gold_sold
      end
    end

    if lot.sell_date
      # The shares themselves were sold, so record a CapitalChange for
      # that, using the adjusted cost basis since portions of the
      # initial investment were already sold in the form of gold.
      changes << CapitalChange.new(adjusted_cost_basis, lot.sell_price,
                                   lot.buy_date, lot.sell_date, lot)
    end
  end

  changes.sort_by! { |c| [c.sell_date, c.buy_date] }

  changes
end

def print_changes(changes)
  puts "%12s  %12s  %-10s  %-10s  %5s" % ['buy ($)', 'sell ($)', 'buy date', 'sell date', 'term']
  last_sell_date = nil
  changes.each do |change|
    puts "%12.6f  %12.6f  %-10s  %-10s  %5s" %
      [
       change.buy_price,
       change.sell_price,
       change.buy_date,
       change.sell_date,
       change.short_term? ? 'short' : 'long'
      ]
    last_sell_date = change.sell_date
  end
  puts
end

def categorize_changes(changes)
  years = {}
  years.default_proc = Proc.new do |hash, key|
    hash[key] = { short: { proceeds: 0, cost: 0 }, long: { proceeds: 0, cost: 0 } }
  end

  changes.each do |change|
    term = change.short_term? ? :short : :long
    bucket = years[change.sell_date.year][term]
    bucket[:proceeds] += change.proceeds
    bucket[:cost] += change.cost
  end

  years
end

def print_tax_year_records(years)
  years.each do |year, record|
    puts "#{year}:"
    record.each do |term, info|
      puts "  #{term}: "
      puts "    proceeds: %12.6f" % info[:proceeds]
      puts "    cost:     %12.6f" % info[:cost]
    end
  end
end

transactions_csv = File.read('my_transactions.csv')
transactions = parse_transactions(transactions_csv)

lots = break_into_lots(transactions)

check_lots(lots, transactions)
print_lots(lots)

proceeds_csv = File.read('proceeds.csv')
proceeds = parse_proceeds(proceeds_csv)

changes = calculate_gold_sales(lots, proceeds)
print_changes(changes)

tax_year_records = categorize_changes(changes)
print_tax_year_records(tax_year_records)
