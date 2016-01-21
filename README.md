# Fast Edit Distance Using Big Data Prefix Trees
Build prefix trees on a big-data platform using a lightning-fast method and use prefix trees to implement fast edit-distance algorithms.

There are three forms of the code included.

The first form is self-contained and run on an HPCC Systems Thor using the in-line dataset in the example.  Use this one to understand what is going on with prefix trees and how to query them in Thor using an edit-distance algorithm.

The second form is mostly the same, but I've written it to take a data file from a Thor, build the prefix tree and then use the same data file to query the prefix tree.  You will need to edit this code for your own data file.  I tested this on a 1.7 million-record dataset with a 21-node Thor using slower spindle storage drives.  The prefix tree builds in about 5 seconds.  The 1.7 million-record dataset is used again to walk the prefix tree in about 45 minutes.  That’s the equivalent of taking two 1.7 million-record datasets and finding all edit-distance candidates between them (think Cartesian join) in 45 minutes.  The naive approach would have to churn through almost 3 trillion candidate pairs.  This approach is orders of magnitude faster.   You can easily edit this example to use different datasets to build and separately query your prefix tree.

The final form of the code is similar to the other two examples, but I broke the code out into an example Thor job and Roxie query.  Like the second form above, you will need to edit this code for your own data file.  The Thor job builds the prefix-tree.  The Roxie query queries the prefix tree interactively and reports back performance data.  Also include is a very simple python script I wrote to query the prefix tree and collect performance data.  I ran a thousand queries on three separate runs using a single-node Roxie with spindle disk drives.  On the final run, the average performance time was 24.7 milliseconds.  The standard deviation for the run was 7.2 milliseconds.  You can see the performance in the second blog post below.

Finally, drop me a line if you've found the blog posts or the code useful.

Read more at:

https://hpccsystems.com/resources/blog/ckaminski/edit-distances-and-optimized-prefix-trees-big-data

https://hpccsystems.com/resources/blog/ckaminski/fast-edit-distance-queries-big-data-using-prefix-trees

https://hpccsystems.com/resources/blog/ckaminski/accelerating-prefix-trees
