// CFK 01/09/2016 charles.kaminski@lexisnexis.com
// This code builds on previous work to add a new concept
//  Use a max and min length to inexpensively prune your
//  prefix tree.
//  Check out "// <***>" to see where edits were made

//==================================================================================================
//=============================== Build Prefix Tree ================================================
//==================================================================================================

WordLayout := RECORD
	STRING   word;
END;

input_ds:= DATASET([{'cant'},{'cat'},{'categories'},{'category'},{'cave'},{'caved'},
                    {'cent'},{'cept'},{'corded'},{'dog'},{'drop'},{'dropping'}], WordLayout);
					
output(input_ds, named('Input_Dataset'));

STRING MarkNodes(STRING l, STRING l_nodes, STRING n, STRING n_nodes) := BEGINC++
	/// This C++ function is designed for use with ECL's Iterate to take a group of 
	/// strings and return the prefix tree node structures in a separate field.
	/// The function requires a sorted list and two passes (one in each direction) 
	/// l is for the last field, n is for the next field, out is for output
	/// nodes contain the indicator of if we should start a node
	/// An initial value of the node for each field is a string of 0 [zeros]
	/// the same length as the string in question plus a "1" for the word endcap
	/// CFK 08/05/2015 charles.kaminski@lexisnexis.com
	#option pure
	#body
    unsigned long i = 0;

	char * out = (char*)rtlMalloc(lenN_nodes);
	memcpy(out, n_nodes, lenN_nodes);
    while ( i < lenN){
        /// If the characters don't match or
        ///   if we are at the end of the last string then
        ///   flip the 0 to a 1 and break out of the loop
        if (l[i] != n[i] || i >= lenL){
            out[i] = '1';
            break;
        }
        if (l_nodes[i] != n_nodes[i]){
            out[i] = '1';
        }
        i += 1;
    }
    __lenResult = lenN_nodes;
    __result   = out;
ENDC++;

NodesLayout := RECORD
	input_ds;
	// The extra '1' in the next statement is a place holder for an end-cap node representing the word itself.
	STRING    nodes      := REGEXREPLACE('.', input_ds.Word, '0') + '1';
	UNSIGNED4 node_cnt   := 0;
	UNSIGNED4 machine    := 0;  // The Thor or Roxie machine this record is on
	DATA      node_ids   := (DATA)''; // Where we pack up the node IDs right before we normalize the prefix tree records
END;

NodesLayout GetPTNodesTransform(NodesLayout L, NodesLayout R) := TRANSFORM
	SELF.nodes    := MarkNodes(L.word, L.nodes, R.word, R.nodes);
	SELF.node_cnt := stringlib.StringFindCount(SELF.nodes,'1');
	SELF.machine  := Thorlib.Node();
	SELF := R;
END;

nodes_format_ds := TABLE(input_ds, NodesLayout);
output(nodes_format_ds, NAMED('Reformatted_List'));

pt_nodes_1_ds := ITERATE(SORT(nodes_format_ds, -word, LOCAL), GetPTNodesTransform(LEFT, RIGHT), LOCAL);
pt_nodes_2_ds := ITERATE(SORT(pt_nodes_1_ds,  word, LOCAL),   GetPTNodesTransform(LEFT, RIGHT), LOCAL);

output(pt_nodes_2_ds, named('Find_PT_Nodes'));

STRING AssignNodeIDs(STRING l, STRING l_nodes, UNSIGNED4 l_node_cnt, STRING l_node_ids,
                     STRING n, STRING n_nodes, UNSIGNED4 n_node_cnt, UNSIGNED4 machine) := BEGINC++
	/// This C++ function is designed for use with ECL's Iterate
	/// It assigns ID's to prefix tree nodes so that the nodes can later be broken out into 
	/// individual records with ECL's Normalize.
	/// CFK 08/05/2015 charles.kaminski@lexisnexis.com
	#option pure
	#body		
	unsigned long long last_node_id = 0;
	unsigned long i = 0;
	unsigned long node_cnt = 0;

	// The new value is empty.  
	// Could happen if there are blanks in your word list.
	if (n_node_cnt == 0){
		__lenResult = 0;
		return;
	}
		
	// Initialize <out> with node ID's from the last iteration
	//  But don't go over if there are too many node ID's from the last iteration
	char * out = (char*)rtlMalloc(n_node_cnt * 8);	
	i = (l_node_cnt < n_node_cnt) ? l_node_cnt : n_node_cnt;
	memcpy(out, l_node_ids, i * 8);

	// Find the ID assigned to the last node from the last word.
	//  This will be the starting point to assign new node IDs
	if (l_node_cnt != 0){
		memcpy(&last_node_id, &l_node_ids[(l_node_cnt - 1) * 8], 8);
	}
	else{
		// This is the starting point for node id on each compute node.
		// Setting last_node_id to a value based on the compute node's
		// unique id (machine) ensures that each prefix tree built locally on each 
		// compute node has unique non-overlapping ID's.  An unsigned long long
		// has a maximum value of 9,223,372,036,854,775,807 or 2^64 - 1.   
		// Multiplying machine by 10^14 allows for 92,233 compute nodes  
		// and 72 Trillion prefix tree nodes on each compute node.  These maximums
		// can be adjusted to fit your needs.
		last_node_id = (machine * 100000000000000);
	}

	// Find the first location where the two words don't match
	// And keep track of how many nodes we've seen
	i = 0;
	while (i < lenL && i < lenN){
		if (l[i] != n[i]){
			break;
		}
		if (n_nodes[i] == '1'){
			node_cnt += 1;
		}
		i += 1;
	}
		
	// Start adding new node ids to <out> from where we left off
	while (i < lenN){
		if (n_nodes[i] == '1'){
			last_node_id += 1;
			node_cnt += 1;
			memcpy(&out[(node_cnt-1)*8], &last_node_id, 8);
		}
		i += 1;
	}
		
	// Add the final node id for the end-cap (referenced in comments at the top)
	last_node_id += 1;
	node_cnt +=1;
	memcpy(&out[(node_cnt-1)*8], &last_node_id, 8);

    __lenResult = n_node_cnt * 8;
    __result    = out;
ENDC++;

NodesLayout GetNodeIdsTransform(NodesLayout L, NodesLayout R) := TRANSFORM
	SELF.machine  := Thorlib.Node();
	SELF.node_ids := (DATA) AssignNodeIDs(L.word, L.nodes, L.node_cnt, (STRING) L.node_ids,
                                          R.word, R.nodes, R.node_cnt, SELF.machine);
	//SELF.node_ids := (DATA) stringlib.stringrepeat('0', R.node_cnt * 8);
	
	SELF := R;
END;

node_ids_ds := ITERATE(SORT(pt_nodes_2_ds,  word), GetNodeIdsTransform(LEFT, RIGHT), LOCAL);

output(node_ids_ds, named('Get_Node_IDs'));

PTLayout := RECORD
	UNSIGNED  id;       // Primary Key
	UNSIGNED  parent_id;// The parent for this node.  Zero is a root node
	STRING    node;     // Contains the payload for this node
	// <***>
	UNSIGNED1 _max;     // The max length of any child word for this node
	UNSIGNED1 _min;     // The min length of any child word for this node	
	// <***>
	BOOLEAN   is_word;  // Indicates if this node is a word (an end-cap with no children)
	UNSIGNED4 machine;  // The Thor machine this prefix tree node is on
END;

UNSIGNED GetID(STRING node_ids, UNSIGNED4 node_to_retrieve) := BEGINC++
	/// Function returns a numeric node id from a group of node ids
	/// CFK 08/05/2015 charles.kaminski@lexisnexis.com
	#option pure
	#body	
	unsigned long long node_id = 0;
	if (node_to_retrieve != 0){
		memcpy(&node_id, &node_ids[(node_to_retrieve - 1) * 8], 8);
	}
	return node_id;
ENDC++;

STRING GetNode(STRING word, STRING nodes, UNSIGNED4 node_to_retrieve):= BEGINC++
	/// Function returns the substring associated with a node
	/// CFK 08/05/2015 charles.kaminski@lexisnexis.com
	#option pure
	#body	
	unsigned int i = 0;
	unsigned int j = 0;
	unsigned int k = 0;
	
	// find the start (i) of the node in question
	while(i < lenNodes){
		if(nodes[i] == '1'){
			j +=1;
		}
		if (j==node_to_retrieve){
			break;
		}
		i += 1 ;
	}
	
	j = i + 1;
	
	// find the end (j) of the node in question
	while(j < lenNodes){
		if (nodes[j] == '1'){
			break;
		}
		j += 1;
	}
	
	k = j - i;
	char * out = (char*)rtlMalloc(k);
	memcpy(&out[0], &word[i], k);

	__lenResult = k;
	__result   = out;
ENDC++;

PTLayout NormalizePTTransform(NodesLayout L, UNSIGNED4 C):= TRANSFORM
	SELF.id        := GetID((STRING)L.node_ids, C);
	SELF.parent_id := GetID((STRING)L.node_ids, C-1);
	SELF.node      := IF(C=L.node_cnt, L.word, GetNode(L.word, L.nodes, C));
	// <***>
	SELF._max      := LENGTH(L.word);
	SELF._min      := LENGTH(L.word);
	// <***>
	SELF.is_word   := IF(C=L.node_cnt, True, False);
	SELF.machine   := Thorlib.Node();
END; 

/// Break each word record into multiple node records
normalized_pt_ds := NORMALIZE(node_ids_ds, LEFT.node_cnt, NormalizePTTransform(LEFT,COUNTER));

output(normalized_pt_ds, named('Normalized_PT'));

// <***>
sorted_normalized_pt_ds := SORT(normalized_pt_ds, id, LOCAL);

PTLayout RollupPTTransform(PTLayout L, PTLayout R):=TRANSFORM
  SELF._max := MAX(L._max, R._max);
	SELF._min := MIN(L._min, R._min);
  SELF := R;
END;

final_pt_ds := Rollup(sorted_normalized_pt_ds, LEFT.id = RIGHT.id, RollupPTTransform(LEFT, RIGHT), LOCAL);
//final_pt_ds := DEDUP(SORT(normalized_pt_ds, id, LOCAL),machine, id, KEEP 1, LEFT, LOCAL);
// <***>

output(final_pt_ds, named('Final_PT'));

//==================================================================================================
//=========================== Query Prefix Tree With Edit Distance Algorythm =======================
//==================================================================================================

STRING CalculateLevenshteinVector(STRING word, STRING node, STRING state) := BEGINC++
	/// CFK 08/20/2015 charles.kaminski@lexisnexis.com                 
	/// This C++ returns the vector used to calculate
	///  the Levenshtein distance in an interative process so that
	///  an efficient trie structure can be traversed when finding candidates
	/// Node values can be passed in and the current state can be saved 
	///   in the return vector so that other nodes can be further processed in series
	/// We're using char arrays to keep the size down
	/// That also means that all our words (both in the trie and our query words)
	///  must be less than 255 characters in length.  If that limitation becomes a problem
	///  we can easily use an array of integers or another other structure to store
	///  intermediate values.
	#option pure
	#include <algorithm>
	#body
	//  The last element in the array will hold
	//   the min value.  The min value will be used later.
	int v_size = lenWord + 2;
	
	unsigned char min_value = 255;
	unsigned char new_value = 0;
	
	// Since v0 is not returned, we should not use rtlMalloc
	//unsigned char * v0 = (unsigned char*)rtlMalloc(v_size);	
	unsigned char v0[v_size];
	// We use rtlMalloc helper function when a variable is returned by the function
	unsigned char * v1 = (unsigned char*)rtlMalloc(v_size);
	
	if (lenState < 1){
		for (int i = 0; i < v_size; i++){
			v0[i] = i;
		}
	}
	else{
		memcpy(&v0[0], &state[0], v_size);
	}
	
	int cost = 0;
	int k = v0[0];
					
	for (int i=k; i<k+lenNode; i++)
	{
		min_value = 255;
		v1[0] = i + 1;
		for (int j=0; j<lenWord; j++)
		{
			cost = (node[i-k] == word[j]) ? 0 : 1;
			new_value = std::min(v1[j] + 1, std::min(v0[j+1] + 1, v0[j] + cost));
			v1[j+1] = new_value;
			if (new_value < min_value){
			  min_value=new_value;
      }
		}
		memcpy(&v0[0], &v1[0], lenState);
	}
	
	// Store the min_value;
	v1[v_size-1] = min_value;
	
	__lenResult = v_size;
  __result    = (char *) v1;
                                                                
ENDC++;
 
UNSIGNED1 GetMinDistance(STRING state) := BEGINC++
	/// CFK 08/20/2015 charles.kaminski@lexisnexis.com	
	///  Get the Minimum Edit Distance
	#option pure
	#body		
	//return (unsigned char) state[(unsigned int) position];
	return (unsigned char) state[lenState-1];
ENDC++;

UNSIGNED1 GetFinalDistance(STRING state) := BEGINC++
	/// CFK 08/20/2015 charles.kaminski@lexisnexis.com	
	///  Get the Final Edit Distance
	#option pure
	#body		
	//return (unsigned char) state[(unsigned int) position];
	return (unsigned char) state[lenState-2];
ENDC++;

QueryPTLayout := RECORD
	input_ds;
	STRING    state                := '';
	DATA      state_data           := (DATA)'ab';
	UNSIGNED  node_id              := 0;
	STRING    node                 := '';
	// <***>
	UNSIGNED1 _max                 := 255;
	UNSIGNED1 _min                 := 0;
	// <***>
	BOOLEAN   is_word              := False;
	STRING    cumulative_nodes     := '';
	UNSIGNED1 cumulative_node_size := 0;
	UNSIGNED1 current_distance     := 0;
	UNSIGNED1 final_distance       := 0;
END;

query_ds := PROJECT(input_ds, QueryPTLayout);

output(query_ds, named('Query_DS'));

QueryPTLayout QueryPTTransform(QueryPTLayout L, PTLayout R) := TRANSFORM
	SELF.word                 := L.word;    // The query word
	SELF.state                := IF(R.is_word, L.state, CalculateLevenshteinVector(L.word, R.node, L.state));
	SELF.state_data			      := (DATA)SELF.state; // The state data reformatted for easier debugging
	SELF.node_id              := R.id;      // The current node ID of the prefix tree.  
	                                        // This will be joined against parent id to find the next node
	SELF.node                 := R.node;    // The text of the node
	// <***>
	SELF._max                 := R._max;    // The minimum word size for all the children of this node
	SELF._min                 := R._min;    // The maximum word size for all the children of this node
	// <***>
	SELF.is_word              := R.is_word; // If true, this is an end-cap word in the tree and has no children
	SELF.cumulative_node_size := IF(R.is_word, LENGTH(R.node), LENGTH(R.node) + L.cumulative_node_size);
	SELF.cumulative_nodes     := IF(R.is_word, R.node, L.cumulative_nodes + R.node);  // The node and it's parent values put together
	SELF.current_distance     := IF(R.is_word, L.current_distance, GetMinDistance(SELF.state));
	SELF.final_distance       := IF(R.is_word, GetFinalDistance(SELF.state), L.final_distance);	
END;

INTEGER1 MAX_DISTANCE := 2;

looped_ds := LOOP(query_ds, 
					LEFT.is_word = False,
					EXISTS(ROWS(LEFT)) = True,
					JOIN(ROWS(LEFT), final_pt_ds, LEFT.node_id = RIGHT.parent_id AND 
					                              LEFT.current_distance <= MAX_DISTANCE AND
								      // <***>
								      // Current_distance cannot be incorporated into the next two expressions
								      // To do so would "double count" certain edit-distance situations;
								      // such as comparing "dog" and "drop" (see testing joins below).
								      // Don't do this -> (LENGTH(LEFT.word)) >= (RIGHT._min - (MAX_DISTANCE - LEFT.current_distance))
								      (LENGTH(LEFT.word)) <= (RIGHT._max + MAX_DISTANCE) AND
								      (LENGTH(LEFT.word)) >= (RIGHT._min - MAX_DISTANCE) ,
								      // <***>
							 QueryPTTransform(LEFT,RIGHT), INNER)); 														 

OUTPUT(looped_ds(looped_ds.final_distance <= MAX_DISTANCE), NAMED('Final'));

/*
looped_ds_orig := LOOP(query_ds, 
					LEFT.is_word = False,
					EXISTS(ROWS(LEFT)) = True,
					JOIN(ROWS(LEFT), final_pt_ds, LEFT.node_id = RIGHT.parent_id AND 
					                              LEFT.current_distance <= MAX_DISTANCE,
							 QueryPTTransform(LEFT,RIGHT), INNER)); 														 

OUTPUT(looped_ds_orig(looped_ds_orig.final_distance <= MAX_DISTANCE), NAMED('Final_Orig'));
*/

/*
/// For testing
QueryTrieLoopBody_ds1 := JOIN(query_ds(word='dog'), final_pt_ds,  LEFT.node_id=RIGHT.parent_id AND LEFT.current_distance <= MAX_DISTANCE, QueryPTTransform(LEFT,RIGHT), INNER);
output(QueryTrieLoopBody_ds1, NAMED('QueryTrieLoopBody_ds1'));

QueryTrieLoopBody_ds2 := JOIN(QueryTrieLoopBody_ds1, final_pt_ds, LEFT.node_id=RIGHT.parent_id AND LEFT.current_distance <= MAX_DISTANCE, QueryPTTransform(LEFT,RIGHT), INNER);
output(QueryTrieLoopBody_ds2, NAMED('QueryTrieLoopBody_ds2'));

QueryTrieLoopBody_ds3 := JOIN(QueryTrieLoopBody_ds2, final_pt_ds, LEFT.node_id=RIGHT.parent_id AND LEFT.current_distance <= MAX_DISTANCE, QueryPTTransform(LEFT,RIGHT), INNER);
output(QueryTrieLoopBody_ds3, NAMED('QueryTrieLoopBody_ds3'));
*/



