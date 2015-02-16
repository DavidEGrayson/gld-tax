This is a Ruby script that helps you calculate the taxes owed on your SPDR GLD ETF investments.  It uses FIFO accounting.  It currently only supports transactions in 2013 and 2014.  It is only for investors paying U.S. taxes.

To use this script, create a file called `my_transactions.csv` that contains every purchase and sale of GLD.  It should look like this:

````
2013-06-07,buy,6.0267,121.01
2013-12-25,buy,2.1234,120.80
2014-08-20,sell,5.0212,132.63
````

Each transaction is a single line with four columns: date, type, share quantity, and price per share in dollars.  (The transaction fees charged by your broker do not get entered here and the script has no features for dealing with them.  Maybe that should be added.)

Save `my_transactions.csv` to the same folder where the script is.  Then navigate to that directory in a shell and run the script:

````
ruby compute.rb
````

It should output a lot of stuff, but the last part is the most useful and it should look something like this:

````
2013:
  short:
    proceeds:     2.996835
    cost:         3.096594
  long:
    proceeds:     0.000000
    cost:         0.000000
2014:
  short:
    proceeds:     9.631280
    cost:         9.897947
  long:
    proceeds:     1.102617
    cost:         1.625691
````

Note: If you sold GLD, the cost and proceeds numbers will be sums of the numbers that come from selling the shares themselves as well as the numbers that come from the gold that the fund sold on your behalf.  I am not sure if that is a problem.

You can use these numbers to fill out Form 8949.

Disclaimer
====

I am not a tax expert.  It is your responsibility to make sure your tax return is correct, and this is just a tool that might help.